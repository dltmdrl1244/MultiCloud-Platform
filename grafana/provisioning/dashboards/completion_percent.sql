with dags_processar as (
        select *
        from public.dag
        where
            dag_id in ($Dags)
    ),
    task_avg as (
        select
            ti.dag_id,
            ti.task_id,
            round(avg(ti.duration)) avg_duration_seconds,
            count(1) total_execution_times
        from dags_processar dp
            inner join task_instance ti on ti.dag_id = dp.dag_id
        where
            ti.start_date >= start_date - interval '60 day'
            and ti.state = 'success'
        group by
            ti.dag_id,
            ti.task_id
        order by 1, 2
    ), tmp as(
        select
            dr.*,
            rank() over (
                partition by dr.dag_id
                order by id desc
            ) as rk
        from dag_run dr
            inner join dags_processar dp on dp.dag_id = dr.dag_id
    ), dags_last_execution as (
        select *
        from tmp
        where
            rk = 1
    ),
    last_execution_tasks as (
        select
            ti.dag_id,
            ti.task_id,
            ti.state,
            ti.start_date,
            round(
                EXTRACT(
                    EPOCH
                    FROM (
                            coalesce(
                                ti.end_date,
                                current_timestamp
                            ) - ti.start_date
                        )
                )
            ) as last_duration
        from dags_last_execution dle
            inner join task_instance ti on dle.dag_id = ti.dag_id
    ), temp_last_execution_rules as (
        select
            let.dag_id,
            let.task_id,
            let.state,
            case
                when let.last_duration > 900
                and let.last_duration >= ta.avg_duration_seconds * 1.3
                and total_execution_times > 10 then 'CRITICAL'
                when let.last_duration > 180
                and let.last_duration >= ta.avg_duration_seconds * 1.3
                and total_execution_times > 10 then 'WARNING'
                else 'OK'
            end message,
            let.last_duration,
            ta.avg_duration_seconds,
            total_execution_times,
            case
                when let.state = 'success' then ta.avg_duration_seconds - let.last_duration
                else 0
            end dif_between_avg_and_last
        from last_execution_tasks let
            left join task_avg ta on let.dag_id = ta.dag_id and let.task_id = ta.task_id
    )
select
    ti.dag_id,
    sum(avg_duration_seconds) FILTER (
        WHERE
            ti.state = 'success'
    ) / sum(avg_duration_seconds) as Percentual --  sum(avg_duration_seconds)   FILTER (WHERE ti.state = 'success') / sum(avg_duration_seconds) as percentual_conclusao_num
from dags_last_execution dle
    inner join temp_last_execution_rules ti on dle.dag_id = ti.dag_id
group by
    ti.dag_id,
    dle.start_date,
    dle.state