-- {"query": "441.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3330} 
with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.websiteurl,
        u.creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location,
        date_trunc('month', u.creationdate) as cohort_month,
        count(*) over () as total_users_snapshot
    from users u
    where u.lastaccessdate >= now() - interval '365 days'
),
user_badge_aggs as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        min(b.date) as first_badge_at,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
post_base as (
    select
        p.id,
        p.owneruserid,
        p.posttypeid,
        p.score,
        p.viewcount,
        p.creationdate,
        p.lastactivitydate,
        p.tags,
        p.title,
        p.acceptedanswerid,
        p.parentid,
        p.answercount,
        p.commentcount,
        case
            when p.tags is not null and position('<sql>' in lower(p.tags)) > 0 then 1
            else 0
        end as has_sql_tag,
        case
            when p.tags is not null and position('<performance>' in lower(p.tags)) > 0 then 1
            else 0
        end as has_performance_tag
    from posts p
    where p.posttypeid in (1,2) -- Questions and Answers
),
question_answer_map as (
    select
        q.id as question_id,
        q.owneruserid as question_owner_id,
        q.creationdate as question_created,
        q.score as question_score,
        q.viewcount as question_views,
        q.tags as question_tags,
        q.title as question_title,
        q.has_sql_tag,
        q.has_performance_tag,
        a.id as answer_id,
        a.owneruserid as answer_owner_id,
        a.creationdate as answer_created,
        a.score as answer_score
    from post_base q
    left join post_base a
      on a.parentid = q.id
    where q.posttypeid = 1
),
qa_windowed as (
    select
        qam.*,
        count(a.answer_id) over (partition by qam.question_id) as total_answers,
        max(a.answer_score) over (partition by qam.question_id) as max_answer_score,
        min(a.answer_score) over (partition by qam.question_id) as min_answer_score,
        avg(a.answer_score) over (partition by qam.question_id) as avg_answer_score,
        row_number() over (partition by qam.question_id order by coalesce(a.answer_score, -2147483648) desc, a.answer_id) as answer_rank_by_score
    from question_answer_map qam
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) as total_votes
    from votes v
    group by v.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.score) as max_comment_score,
        avg(c.score) filter (where c.score is not null) as avg_comment_score,
        max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
closed_events as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_code
    from posthistory ph
    where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)
    group by ph.postid
),
duplicate_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        min(pl.creationdate) as first_dup_link_at,
        count(*) as dup_link_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
tag_unroll as (
    select
        p.id as post_id,
        lower(trim(tg)) as tag
    from posts p
    cross join lateral unnest(string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><')) as tg
    where p.tags is not null and p.posttypeid = 1
),
tag_stats as (
    select
        tu.post_id,
        count(*) as tag_count,
        sum(case when tu.tag in ('sql','performance','tuning','postgresql','mysql','sql-server') then 1 else 0 end) as perf_related_tag_hits
    from tag_unroll tu
    group by tu.post_id
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions_posted,
        count(*) filter (where p.posttypeid = 2) as answers_posted,
        sum(p.score) as total_post_score,
        max(p.lastactivitydate) as last_post_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
accepted_map as (
    select
        q.id as question_id,
        q.acceptedanswerid,
        case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted
    from posts q
    where q.posttypeid = 1
),
top_answer_per_q as (
    select
        qaw.question_id,
        qaw.answer_id as top_answer_id,
        qaw.answer_owner_id as top_answer_user_id,
        qaw.answer_score as top_answer_score
    from qa_windowed qaw
    where qaw.answer_rank_by_score = 1 and qaw.answer_id is not null
),
user_rankings as (
    select
        ru.user_id,
        ru.displayname,
        ru.norm_location,
        ru.reputation,
        ua.questions_posted,
        ua.answers_posted,
        ua.total_post_score,
        ub.total_badges,
        dense_rank() over (order by coalesce(ua.answers_posted,0) desc, coalesce(ua.questions_posted,0) desc, ru.reputation desc) as activity_rank
    from recent_active_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badge_aggs ub on ub.userid = ru.user_id
),
question_quality as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.score as q_score,
        q.viewcount as q_views,
        coalesce(v.upvotes,0) as q_up,
        coalesce(v.downvotes,0) as q_down,
        coalesce(v.favorites,0) as q_fav,
        coalesce(v.bounty_started,0) as bounty_started,
        coalesce(v.bounty_awarded,0) as bounty_awarded,
        coalesce(ca.comment_count,0) as q_comment_count,
        coalesce(ca.avg_comment_score,0) as q_avg_comment_score,
        ts.tag_count,
        ts.perf_related_tag_hits,
        ce.first_closed_at,
        ce.last_closed_at,
        ce.last_close_reason_code,
        case
            when q.viewcount is null or q.viewcount = 0 then null
            else round((q.score::numeric + coalesce(v.upvotes,0) - coalesce(v.downvotes,0) + coalesce(v.favorites,0) / 2.0) / nullif(q.viewcount,0), 6)
        end as engagement_ratio
    from posts q
    left join votes_agg v on v.postid = q.id
    left join comments_agg ca on ca.postid = q.id
    left join tag_stats ts on ts.post_id = q.id
    left join closed_events ce on ce.postid = q.id
    where q.posttypeid = 1
),
answer_quality as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.score as a_score,
        coalesce(v.upvotes,0) as a_up,
        coalesce(v.downvotes,0) as a_down,
        coalesce(ca.comment_count,0) as a_comment_count,
        coalesce(ca.max_comment_score,0) as a_max_comment_score
    from posts a
    left join votes_agg v on v.postid = a.id
    left join comments_agg ca on ca.postid = a.id
    where a.posttypeid = 2
),
final_candidates as (
    select
        qq.question_id,
        qq.asker_id,
        qq.q_score,
        qq.q_views,
        qq.q_up,
        qq.q_down,
        qq.q_fav,
        qq.bounty_started,
        qq.bounty_awarded,
        qq.q_comment_count,
        qq.q_avg_comment_score,
        qq.tag_count,
        qq.perf_related_tag_hits,
        qq.first_closed_at,
        qq.last_closed_at,
        qq.last_close_reason_code,
        qq.engagement_ratio,
        am.has_accepted,
        case when am.has_accepted = 1 then 'Accepted' else 'Unaccepted' end as accepted_state,
        tapq.top_answer_id,
        tapq.top_answer_user_id,
        tapq.top_answer_score,
        aq.a_up as top_answer_up,
        aq.a_down as top_answer_down,
        aq.a_comment_count as top_answer_comments,
        aq.a_max_comment_score as top_answer_max_comment_score
    from question_quality qq
    left join accepted_map am on am.question_id = qq.question_id
    left join top_answer_per_q tapq on tapq.question_id = qq.question_id
    left join answer_quality aq on aq.answer_id = tapq.top_answer_id
),
user_joined as (
    select
        fc.*,
        ur.displayname as asker_name,
        ur.norm_location as asker_location,
        ur.reputation as asker_reputation,
        ur.activity_rank as asker_activity_rank,
        ur2.displayname as top_answerer_name,
        ur2.norm_location as top_answerer_location,
        ur2.reputation as top_answerer_reputation,
        ur2.activity_rank as top_answerer_activity_rank
    from final_candidates fc
    left join user_rankings ur on ur.user_id = fc.asker_id
    left join user_rankings ur2 on ur2.user_id = fc.top_answer_user_id
),
scored as (
    select
        uj.*,
        coalesce(uj.engagement_ratio, 0)::numeric +
        coalesce(uj.q_up - uj.q_down, 0)::numeric / 10 +
        coalesce(uj.top_answer_score, 0)::numeric / 5 +
        case when uj.perf_related_tag_hits > 0 then 0.2 * uj.perf_related_tag_hits else 0 end +
        case when uj.has_accepted = 1 then 0.5 else 0 end -
        case when uj.first_closed_at is not null then 0.4 else 0 end as perf_benchmark_score
    from user_joined uj
),
bounded as (
    select
        s.*,
        ntile(10) over (order by s.perf_benchmark_score desc nulls last) as decile,
        rank() over (order by s.perf_benchmark_score desc nulls last, s.q_views desc nulls last, s.q_score desc nulls last) as global_rank
    from scored s
),
sampled as (
    (
        select * from bounded
        where perf_related_tag_hits > 0
        order by perf_benchmark_score desc nulls last
        limit 200
    )
    union all
    (
        select * from bounded
        where perf_related_tag_hits = 0 and tag_count >= 3 and q_views > 0
        order by random()
        limit 100
    )
)
select
    b.global_rank,
    b.decile,
    b.question_id,
    coalesce(p.title, '(no title)') as question_title,
    coalesce(replace(replace(lower(coalesce(p.tags,'')), '<', ' <'), '>', '> '), '') as spaced_tags,
    b.accepted_state,
    b.q_score,
    b.q_views,
    b.q_up,
    b.q_down,
    b.q_fav,
    b.bounty_started,
    b.bounty_awarded,
    b.q_comment_count,
    round(b.engagement_ratio::numeric, 6) as engagement_ratio,
    b.perf_related_tag_hits,
    b.first_closed_at,
    b.last_close_reason_code,
    b.top_answer_id,
    b.top_answer_score,
    b.top_answer_up,
    b.top_answer_down,
    b.top_answer_comments,
    b.top_answer_max_comment_score,
    b.asker_id,
    b.asker_name,
    b.asker_location,
    b.asker_reputation,
    b.asker_activity_rank,
    b.top_answerer_name,
    b.top_answerer_location,
    b.top_answerer_reputation,
    b.top_answerer_activity_rank,
    round(b.perf_benchmark_score::numeric, 6) as perf_benchmark_score,
    coalesce(vq.total_votes,0) as q_total_votes,
    coalesce(va.total_votes,0) as a_total_votes,
    case when b.perf_benchmark_score > percentile_disc(0.9) within group (order by b.perf_benchmark_score) over () then 'P90+'
         when b.perf_benchmark_score > percentile_disc(0.75) within group (order by b.perf_benchmark_score) over () then 'P75+'
         else 'Baseline' end as score_bucket
from sampled b
left join posts p on p.id = b.question_id
left join votes_agg vq on vq.postid = b.question_id
left join votes_agg va on va.postid = b.top_answer_id
where
    (b.q_views is not null and b.q_views > 0)
    and (
        b.perf_related_tag_hits > 0
        or (b.engagement_ratio is not null and b.engagement_ratio > 0)
        or (b.top_answer_score is not null and b.top_answer_score >= 0)
    )
order by
    b.decile,
    b.global_rank
limit 300;