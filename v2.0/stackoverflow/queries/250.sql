-- {"query": "250.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3434}
with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl,
        u.upvotes,
        u.downvotes,
        u.views,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(case when p.posttypeid = 1 then 1 end) as q_count,
        count(case when p.posttypeid = 2 then 1 end) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) as total_views,
        max(p.lastactivitydate) as last_active_at
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(case when c.score > 0 then 1 else 0 end) as pos_comment_count,
        avg(nullif(c.score, 0)) as avg_nonzero_comment_score
    from comments c
    where c.userid is not null
    group by c.userid
),
badge_pivot as (
    select
        b.userid as user_id,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(case when b.tagbased = true then 1 end) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
post_quality as (
    select
        p.owneruserid as user_id,
        (select avg(mv) from (
            select mv from (
                select coalesce(p2.score,0) as mv,
                       row_number() over (order by coalesce(p2.score,0)) as rn,
                       count(*) over () as cnt
                from posts p2
                where p2.owneruserid = p.owneruserid
            ) t where rn in (floor((cnt+1)/2.0), ceil((cnt+1)/2.0))
        ) med) as median_post_score,
        avg(case when p.posttypeid = 1 then p.score end) as avg_question_score,
        avg(case when p.posttypeid = 2 then p.score end) as avg_answer_score,
        avg(nullif(p.commentcount,0)) as avg_nonzero_commentcount,
        sum(case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end) as accepted_questions,
        sum(case when p.posttypeid = 2 and p.id in (select acceptedanswerid from posts where acceptedanswerid is not null) then 1 else 0 end) as accepted_answers
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
dup_network as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.linktypeid,
        case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
    where pl.linktypeid in (1,3)
),
question_tags as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
    from posts p
    where p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
),
tag_influence as (
    select
        qt.user_id,
        count(*) as tag_uses,
        count(distinct qt.tag) as distinct_tags,
        max(case when qt.tag like 'sql%' or qt.tag like 'postgres%' then qt.tag end) as sample_db_tag,
        sum(case when lower(qt.tag) in ('sql','postgresql','postgres','tsql','mysql') then 1 else 0 end) as db_tag_uses
    from question_tags qt
    group by qt.user_id
),
close_events as (
    select
        ph.postid,
        ph.userid as actor_user_id,
        ph.creationdate as closed_at,
        ph.comment as close_reason_id,
        case
            when ph.comment ~ '^[0-9]+$' then cast(ph.comment as integer)
            else null
        end as close_reason_int
    from posthistory ph
    where ph.posthistorytypeid = 10
),
user_closure as (
    select
        p.owneruserid as user_id,
        count(case when ce.postid is not null then 1 end) as closed_questions,
        count(case when ce.close_reason_int = 101 then 1 end) as duplicate_closed_questions,
        min(ce.closed_at) as first_closed_at,
        max(ce.closed_at) as last_closed_at
    from posts p
    left join close_events ce on ce.postid = p.id
    where p.posttypeid = 1 and p.owneruserid is not null
    group by p.owneruserid
),
vote_aggs as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    group by v.postid
),
user_vote_rollup as (
    select
        p.owneruserid as user_id,
        sum(coalesce(va.upvotes,0)) as received_upvotes,
        sum(coalesce(va.downvotes,0)) as received_downvotes,
        sum(coalesce(va.bounty_started,0)) as total_bounty_started_on_posts,
        sum(coalesce(va.bounty_awarded,0)) as total_bounty_awarded_on_posts
    from posts p
    left join vote_aggs va on va.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
activity_timeline as (
    select
        ua.user_id,
        date_trunc('month', p.creationdate) as month,
        count(case when p.posttypeid = 1 then 1 end) as q_month,
        count(case when p.posttypeid = 2 then 1 end) as a_month
    from user_activity ua
    join posts p on p.owneruserid = ua.user_id
    group by ua.user_id, date_trunc('month', p.creationdate)
),
user_trends as (
    select
        user_id,
        month,
        q_month,
        a_month,
        sum(q_month + a_month) over (partition by user_id order by month rows between unbounded preceding and current row) as cum_posts,
        avg(q_month + a_month) over (partition by user_id order by month rows between 2 preceding and current row) as mov_avg_3m_posts,
        lag(q_month + a_month, 1) over (partition by user_id order by month) as prev_month_posts
    from activity_timeline
),
top_k as (
    select
        ru.id as user_id,
        dense_rank() over (order by coalesce(ua.total_post_score,0) desc, coalesce(uv.received_upvotes,0) desc, ru.reputation desc) as rnk
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.id
    left join user_vote_rollup uv on uv.user_id = ru.id
),
user_dimensions as (
    select
        ru.id as user_id,
        ru.displayname,
        ru.reputation,
        ru.norm_location,
        ru.websiteurl,
        ru.upvotes as profile_upvotes,
        ru.downvotes as profile_downvotes,
        ru.views as profile_views,
        ua.q_count,
        ua.a_count,
        ua.total_post_score,
        ua.total_views as post_views,
        ua.last_active_at,
        cs.comment_count,
        cs.pos_comment_count,
        cs.avg_nonzero_comment_score,
        bp.gold_badges,
        bp.silver_badges,
        bp.bronze_badges,
        bp.tag_badges,
        bp.first_badge_date,
        bp.last_badge_date,
        pq.median_post_score,
        pq.avg_question_score,
        pq.avg_answer_score,
        pq.avg_nonzero_commentcount,
        pq.accepted_questions,
        pq.accepted_answers,
        ti.tag_uses,
        ti.distinct_tags,
        ti.sample_db_tag,
        ti.db_tag_uses,
        uc.closed_questions,
        uc.duplicate_closed_questions,
        uv.received_upvotes,
        uv.received_downvotes,
        uv.total_bounty_started_on_posts,
        uv.total_bounty_awarded_on_posts
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.id
    left join comment_stats cs on cs.user_id = ru.id
    left join badge_pivot bp on bp.user_id = ru.id
    left join post_quality pq on pq.user_id = ru.id
    left join tag_influence ti on ti.user_id = ru.id
    left join user_closure uc on uc.user_id = ru.id
    left join user_vote_rollup uv on uv.user_id = ru.id
),
null_safety as (
    select
        ud.*,
        coalesce(ud.q_count,0) + coalesce(ud.a_count,0) as total_posts,
        coalesce(ud.received_upvotes,0) - coalesce(ud.received_downvotes,0) as net_received_votes,
        coalesce(ud.profile_upvotes,0) - coalesce(ud.profile_downvotes,0) as net_profile_votes,
        case when coalesce(ud.q_count,0) > 0 then round(100.0 * coalesce(ud.accepted_questions,0) / ud.q_count, 2) end as q_accept_rate_pct,
        case when coalesce(ud.a_count,0) > 0 then round(100.0 * coalesce(ud.accepted_answers,0) / ud.a_count, 2) end as a_accept_rate_pct,
        case when coalesce(ud.tag_uses,0) > 0 then round(100.0 * coalesce(ud.db_tag_uses,0) / ud.tag_uses, 2) end as db_tag_focus_pct
    from user_dimensions ud
),
location_rollup as (
    select
        ns.norm_location,
        count(*) as users_in_location,
        avg(coalesce(ns.reputation,0)) as avg_rep_location,
        (select mv from (
            select mv, row_number() over (order by mv) as rn, count(*) over () as cnt
            from (
                select coalesce(total_post_score,0) as mv from null_safety n2 where n2.norm_location = ns.norm_location
            ) x
        ) y where rn = ceil(0.9 * cnt) limit 1) as p90_total_post_score_loc
    from null_safety ns
    group by ns.norm_location
),
user_ranked as (
    select
        ns.*,
        lr.users_in_location,
        lr.avg_rep_location,
        lr.p90_total_post_score_loc,
        row_number() over (order by coalesce(ns.total_post_score,0) desc, coalesce(ns.received_upvotes,0) desc, ns.reputation desc) as global_rownum,
        rank() over (partition by ns.norm_location order by coalesce(ns.total_post_score,0) desc) as location_rank,
        dense_rank() over (order by coalesce(ns.db_tag_uses,0) desc) as db_focus_rank
    from null_safety ns
    left join location_rollup lr on lr.norm_location = ns.norm_location
),
final_users as (
    select
        ur.*,
        tk.rnk as topk_rank,
        coalesce(ur.total_post_score,0) + 2 * coalesce(ur.received_upvotes,0) + 5 * coalesce(ur.gold_badges,0) + 3 * coalesce(ur.silver_badges,0) + coalesce(ur.bronze_badges,0) - coalesce(ur.received_downvotes,0) as composite_score
    from user_ranked ur
    left join top_k tk on tk.user_id = ur.user_id
    where coalesce(ur.total_posts,0) > 0
),
unioned_sample as (
    select * from final_users where composite_score is not null
    union all
    select * from final_users where composite_score is not null and location_rank <= 10
),
scored as (
    select
        u.*,
        (
            select p2.title
            from posts p2
            where p2.owneruserid = u.user_id
            order by coalesce(p2.viewcount,0) desc, p2.id
            limit 1
        ) as top_post_title,
        case
            when u.db_tag_focus_pct is null then 'Unclassified'
            when u.db_tag_focus_pct >= 50 then 'DB-heavy'
            when u.db_tag_focus_pct >= 20 and u.db_tag_focus_pct < 50 then 'Balanced'
            else 'Generalist'
        end as domain_profile,
        lower(regexp_replace(coalesce(u.displayname, 'anonymous'), '[[:space:]]+', '_', 'g')) || '_' || cast(u.user_id as text) as url_slug
    from unioned_sample u
),
aggregate_scores as (
    select
        avg(mv) as median_composite_score,
        (select mv from (
            select mv, row_number() over (order by mv) as rn, count(*) over () as cnt
            from (select composite_score as mv from scored) s1
        ) t where rn = ceil(0.9 * cnt) limit 1) as p90_composite_score,
        min(composite_score) as min_comp,
        max(composite_score) as max_comp
    from (
        select composite_score from scored
        where
            coalesce(total_posts,0) >= 5
            and coalesce(total_post_score,0) + coalesce(received_upvotes,0) - coalesce(received_downvotes,0) >= 0
            and (
                domain_profile in ('DB-heavy','Balanced')
                or (sample_db_tag is not null and coalesce(db_tag_focus_pct,0) >= 10)
                or (coalesce(gold_badges,0) >= 1 and coalesce(a_count,0) > coalesce(q_count,0))
            )
    ) sub,
    lateral (
        select avg(mv) as mv from (
            select mv from (
                select composite_score as mv,
                       row_number() over (order by composite_score) as rn,
                       count(*) over () as cnt
                from scored s2
                where
                    coalesce(total_posts,0) >= 5
                    and coalesce(total_post_score,0) + coalesce(received_upvotes,0) - coalesce(received_downvotes,0) >= 0
                    and (
                        domain_profile in ('DB-heavy','Balanced')
                        or (sample_db_tag is not null and coalesce(db_tag_focus_pct,0) >= 10)
                        or (coalesce(gold_badges,0) >= 1 and coalesce(a_count,0) > coalesce(q_count,0))
                    )
            ) t2 where rn in (floor((cnt+1)/2.0), ceil((cnt+1)/2.0))
        ) med
    ) medcalc
)
select
    s.user_id,
    s.displayname,
    s.url_slug,
    s.reputation,
    s.norm_location,
    s.global_rownum,
    s.location_rank,
    s.db_focus_rank,
    s.topk_rank,
    s.q_count,
    s.a_count,
    s.total_posts,
    s.total_post_score,
    s.post_views,
    s.received_upvotes,
    s.received_downvotes,
    s.net_received_votes,
    s.gold_badges,
    s.silver_badges,
    s.bronze_badges,
    s.tag_badges,
    s.q_accept_rate_pct,
    s.a_accept_rate_pct,
    s.db_tag_focus_pct,
    s.closed_questions,
    s.duplicate_closed_questions,
    s.first_badge_date,
    s.last_badge_date,
    s.last_active_at,
    s.sample_db_tag,
    s.top_post_title,
    s.domain_profile,
    s.composite_score,
    agg.median_composite_score,
    agg.p90_composite_score,
    case
        when agg.max_comp = agg.min_comp then 1.0
        else (cast(s.composite_score as numeric) - cast(agg.min_comp as numeric))
             / nullif(cast(agg.max_comp - agg.min_comp as numeric), 0)
    end as composite_norm_0_1
from scored s
cross join aggregate_scores agg
where
    coalesce(s.total_posts,0) >= 5
    and coalesce(s.total_post_score,0) + coalesce(s.received_upvotes,0) - coalesce(s.received_downvotes,0) >= 0
    and (
        s.domain_profile in ('DB-heavy','Balanced')
        or (s.sample_db_tag is not null and coalesce(s.db_tag_focus_pct,0) >= 10)
        or (coalesce(s.gold_badges,0) >= 1 and coalesce(s.a_count,0) > coalesce(s.q_count,0))
    )
order by
    s.composite_score desc,
    s.received_upvotes desc,
    s.user_id
limit 500;