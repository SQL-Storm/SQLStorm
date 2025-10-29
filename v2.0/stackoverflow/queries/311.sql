-- {"query": "311.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3220}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score, 0)) as post_score_sum,
        avg(nullif(p.viewcount, 0)) as avg_views_nonzero,
        max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_engagement as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(coalesce(c.score,0)) as comment_score_sum,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
vote_summary as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 5) as favorites_cast,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
badge_mix as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_count,
        count(*) filter (where b.class = 2) as silver_count,
        count(*) filter (where b.class = 3) as bronze_count,
        count(*) filter (where coalesce(b.tagbased, false) = true) as tagbadges_count,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_quality as (
    select
        q.owneruserid as user_id,
        count(*) as questions_total,
        count(*) filter (where q.acceptedanswerid is not null) as questions_with_accept,
        avg(case when q.viewcount is null or q.viewcount = 0 then null else cast(q.score as numeric) / nullif(q.viewcount,0) end) as avg_score_per_view,
        percentile_cont(0.9) within group (order by coalesce(q.score,0)) as p90_question_score,
        min(q.creationdate) as first_question_date,
        max(q.creationdate) as last_question_date
    from posts q
    where q.posttypeid = 1 and q.owneruserid is not null
    group by q.owneruserid
),
answer_quality as (
    select
        a.owneruserid as user_id,
        count(*) as answers_total,
        count(*) filter (where exists (
            select 1
            from posts q2
            where q2.id = a.parentid
              and q2.acceptedanswerid = a.id
        )) as answers_accepted,
        avg(coalesce(a.score,0)) as avg_answer_score,
        percentile_cont(0.95) within group (order by coalesce(a.score,0)) as p95_answer_score,
        max(a.creationdate) as last_answer_date
    from posts a
    where a.posttypeid = 2 and a.owneruserid is not null
    group by a.owneruserid
),
tag_influence as (
    select
        q.owneruserid as user_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag_name,
        count(*) as tag_q_count,
        sum(coalesce(q.score,0)) as tag_q_score
    from posts q
    where q.posttypeid = 1 and q.tags is not null and q.owneruserid is not null
    group by q.owneruserid, unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><'))
),
top_tags as (
    select
        tt.user_id,
        string_agg(tt.tag_name || ':' || tt.tag_q_count || '/' || tt.tag_q_score, ', ' order by tt.tag_q_count desc, tt.tag_q_score desc, tt.tag_name asc) as tag_summary,
        count(*) as distinct_tags
    from (
        select
            ti.user_id,
            ti.tag_name,
            ti.tag_q_count,
            ti.tag_q_score,
            row_number() over (partition by ti.user_id order by ti.tag_q_count desc, ti.tag_q_score desc, ti.tag_name asc) as rn
        from tag_influence ti
    ) tt
    where tt.rn <= 5
    group by tt.user_id
),
postlinks_stats as (
    select
        p.owneruserid as user_id,
        count(distinct pl.id) filter (where pl.linktypeid = 1) as linked_refs,
        count(distinct pl.id) filter (where pl.linktypeid = 3) as duplicate_marks,
        count(distinct case when pl.linktypeid = 3 and p.posttypeid = 1 then pl.relatedpostid end) as dup_targets
    from posts p
    left join postlinks pl
      on pl.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
closure_events as (
    select
        ph.postid,
        ph.userid as actor_user_id,
        ph.creationdate,
        ph.comment as close_reason_id,
        ph.text
    from posthistory ph
    where ph.posthistorytypeid in (10,35)
),
user_closed_interactions as (
    select
        p.owneruserid as user_id,
        count(*) as times_closed,
        count(*) filter (where coalesce(ph.close_reason_id,'') in ('101','1')) as times_marked_duplicate,
        min(ph.creationdate) as first_close_date,
        max(ph.creationdate) as last_close_date
    from posts p
    join closure_events ph on ph.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
normalized_user_base as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(u.location, ''), 'Unknown') as location,
        u.websiteurl,
        dense_rank() over (order by coalesce(u.location, 'Unknown'), u.displayname) as location_rank
    from recent_users u
    where u.rn <= 5000
),
activity_enriched as (
    select
        nub.*,
        ua.q_count,
        ua.a_count,
        ua.post_score_sum,
        ua.avg_views_nonzero,
        ua.last_activity,
        co.comment_count,
        co.comment_score_sum,
        co.last_comment_date,
        vs.upvotes_cast,
        vs.downvotes_cast,
        vs.favorites_cast,
        vs.bounty_total,
        vs.last_vote_date,
        bm.badge_count,
        bm.gold_count,
        bm.silver_count,
        bm.bronze_count,
        bm.tagbadges_count,
        bm.last_badge_date,
        qq.questions_total,
        qq.questions_with_accept,
        qq.avg_score_per_view as q_avg_score_per_view,
        qq.p90_question_score,
        qq.first_question_date,
        qq.last_question_date,
        aq.answers_total,
        aq.answers_accepted,
        aq.avg_answer_score,
        aq.p95_answer_score,
        aq.last_answer_date,
        tt.tag_summary,
        tt.distinct_tags,
        pls.linked_refs,
        pls.duplicate_marks,
        pls.dup_targets,
        uci.times_closed,
        uci.times_marked_duplicate,
        uci.first_close_date,
        uci.last_close_date
    from normalized_user_base nub
    left join user_activity ua on ua.user_id = nub.user_id
    left join comment_engagement co on co.user_id = nub.user_id
    left join vote_summary vs on vs.user_id = nub.user_id
    left join badge_mix bm on bm.user_id = nub.user_id
    left join question_quality qq on qq.user_id = nub.user_id
    left join answer_quality aq on aq.user_id = nub.user_id
    left join top_tags tt on tt.user_id = nub.user_id
    left join postlinks_stats pls on pls.user_id = nub.user_id
    left join user_closed_interactions uci on uci.user_id = nub.user_id
),
scored as (
    select
        ae.*,
        coalesce(ae.q_count,0) + coalesce(ae.a_count,0) as total_posts,
        coalesce(ae.questions_with_accept,0) + coalesce(ae.answers_accepted,0) as total_accepts,
        case
            when coalesce(ae.questions_total,0) = 0 then null
            else cast(coalesce(ae.questions_with_accept,0) as numeric) / nullif(ae.questions_total,0)
        end as question_accept_rate,
        case
            when coalesce(ae.answers_total,0) = 0 then null
            else cast(coalesce(ae.answers_accepted,0) as numeric) / nullif(ae.answers_total,0)
        end as answer_accept_rate,
        coalesce(ae.upvotes_cast,0) - coalesce(ae.downvotes_cast,0) as net_votes_cast,
        greatest(coalesce(ae.gold_count,0)*5 + coalesce(ae.silver_count,0)*3 + coalesce(ae.bronze_count,0), 0) as badge_weight_score,
        coalesce(ae.post_score_sum,0) + coalesce(ae.comment_score_sum,0) as total_contrib_score,
        case
            when coalesce(coalesce(ae.q_count,0) + coalesce(ae.a_count,0),0) = 0 then 0
            else (cast(coalesce(ae.post_score_sum,0) as numeric) / nullif(coalesce(ae.q_count,0) + coalesce(ae.a_count,0),0))
        end as avg_score_per_post,
        coalesce(ae.tagbadges_count,0) + least(coalesce(ae.distinct_tags,0), 50) as tag_influence_score,
        coalesce(ae.duplicate_marks,0) - coalesce(ae.times_marked_duplicate,0) as net_duplicate_delta,
        extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - coalesce(ae.last_activity, ae.creationdate))) / 86400.0 as days_since_last_activity
    from activity_enriched ae
),
ranked as (
    select
        s.*,
        (
            coalesce(s.reputation,0) / 1000.0
            + coalesce(s.total_contrib_score,0) / 50.0
            + coalesce(s.badge_weight_score,0) / 10.0
            + coalesce(s.tag_influence_score,0) / 5.0
            + coalesce(s.net_votes_cast,0) / 20.0
            + coalesce(s.total_accepts,0) / 2.0
            - coalesce(s.days_since_last_activity,0) / 30.0
            - greatest(coalesce(s.times_closed,0) - coalesce(s.times_marked_duplicate,0), 0) / 10.0
        ) as composite_score,
        row_number() over (order by
            (
                coalesce(s.reputation,0) / 1000.0
                + coalesce(s.total_contrib_score,0) / 50.0
                + coalesce(s.badge_weight_score,0) / 10.0
                + coalesce(s.tag_influence_score,0) / 5.0
                + coalesce(s.net_votes_cast,0) / 20.0
                + coalesce(s.total_accepts,0) / 2.0
                - coalesce(s.days_since_last_activity,0) / 30.0
                - greatest(coalesce(s.times_closed,0) - coalesce(s.times_marked_duplicate,0), 0) / 10.0
            ) desc,
            s.user_id desc
        ) as rk_desc
    from scored s
),
dupe_check as (
    select user_id from ranked
    intersect
    select user_id from user_activity where q_count > 0 or a_count > 0
),
final_set as (
    select r.*
    from ranked r
    where r.user_id in (select user_id from dupe_check)
      and (
        lower(r.location) like '%united%' or
        position('http' in coalesce(r.websiteurl,'')) > 0 or
        r.tag_summary is not null
      )
)
select
    f.user_id,
    f.displayname,
    f.location,
    f.websiteurl,
    f.reputation,
    f.q_count,
    f.a_count,
    f.total_posts,
    f.total_contrib_score,
    f.avg_score_per_post,
    f.total_accepts,
    f.question_accept_rate,
    f.answer_accept_rate,
    f.badge_count,
    f.gold_count,
    f.silver_count,
    f.bronze_count,
    f.tag_influence_score,
    f.tag_summary,
    f.distinct_tags,
    f.linked_refs,
    f.duplicate_marks,
    f.times_closed,
    f.net_duplicate_delta,
    f.net_votes_cast,
    f.bounty_total,
    f.last_activity,
    f.last_vote_date,
    f.last_badge_date,
    f.last_question_date,
    f.last_answer_date,
    f.days_since_last_activity,
    f.composite_score,
    f.rk_desc as overall_rank,
    case
        when f.composite_score >= (select percentile_cont(0.9) within group (order by composite_score) from final_set) then 'Tier S'
        when f.composite_score >= (select percentile_cont(0.75) within group (order by composite_score) from final_set) then 'Tier A'
        when f.composite_score >= (select percentile_cont(0.5) within group (order by composite_score) from final_set) then 'Tier B'
        when f.composite_score >= (select percentile_cont(0.25) within group (order by composite_score) from final_set) then 'Tier C'
        else 'Tier D'
    end as performance_tier
from final_set f
where not exists (
    select 1
    from posts p
    where p.owneruserid = f.user_id
      and p.posttypeid = 1
      and p.closeddate is not null
      and p.closeddate > coalesce(f.last_activity, f.creationdate)
)
order by f.composite_score desc, f.user_id desc
limit 200;