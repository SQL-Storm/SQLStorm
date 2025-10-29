with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        date_trunc('month', u.creationdate) as signup_month
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_q_views,
        max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    group by v.postid
),
qna as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.creationdate as question_date,
        q.score as q_score,
        q.viewcount as q_views,
        q.title,
        q.tags,
        q.acceptedanswerid,
        va.upvotes as q_up,
        va.downvotes as q_down,
        va.favorites as q_fav
    from posts q
    left join votes_agg va on va.postid = q.id
    where q.posttypeid = 1
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_date,
        a.score as a_score,
        va.upvotes as a_up,
        va.downvotes as a_down
    from posts a
    left join votes_agg va on va.postid = a.id
    where a.posttypeid = 2
),
answer_stats as (
    select
        a.question_id,
        count(*) as answer_count,
        max(a.a_score) as max_answer_score,
        avg(cast(a.a_score as numeric)) as avg_answer_score,
        min(a.answer_date) as first_answer_date,
        max(a.answer_date) as last_answer_date
    from answers a
    group by a.question_id
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        pl.creationdate as dup_link_date
    from postlinks pl
    where pl.linktypeid = 3
),
closed_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_date,
        max(ph.creationdate) as last_closed_date,
        count(*) as close_events,
        max(case when ph.comment ~ '^[0-9]+$' then cast(ph.comment as integer) else null end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid
),
reopened_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_reopen_date,
        count(*) as reopen_events
    from posthistory ph
    where ph.posthistorytypeid = 11
    group by ph.postid
),
hot_bumps as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 50) as community_bumps,
        count(*) filter (where ph.posthistorytypeid = 52) as hot_selected,
        count(*) filter (where ph.posthistorytypeid = 53) as hot_removed
    from posthistory ph
    where ph.posthistorytypeid in (50,52,53)
    group by ph.postid
),
tag_expansion as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
    from qna q
    where q.tags is not null and q.tags like '<%>'
),
tagged_counts as (
    select
        te.tag,
        count(distinct te.question_id) as tagged_questions,
        sum(coalesce(q.q_views,0)) as tagged_views,
        sum(coalesce(q.q_score,0)) as tagged_score
    from tag_expansion te
    join qna q on q.question_id = te.question_id
    group by te.tag
),
user_badges as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where cast(b.tagbased as integer) = 1) as tag_badges
    from badges b
    group by b.userid
),
question_enriched as (
    select
        q.*,
        coalesce(a_stats.answer_count, 0) as answer_count,
        a_stats.max_answer_score,
        a_stats.avg_answer_score,
        a_stats.first_answer_date,
        a_stats.last_answer_date,
        ce.first_closed_date,
        ce.last_closed_date,
        ce.close_events,
        ce.last_close_reason_id,
        re.first_reopen_date,
        re.reopen_events,
        hb.community_bumps,
        hb.hot_selected,
        hb.hot_removed,
        case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted
    from qna q
    left join answer_stats a_stats on a_stats.question_id = q.question_id
    left join closed_events ce on ce.postid = q.question_id
    left join reopened_events re on re.postid = q.question_id
    left join hot_bumps hb on hb.postid = q.question_id
),
user_enriched as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl_norm,
        ru.signup_month,
        coalesce(ua.q_count,0) as q_count,
        coalesce(ua.a_count,0) as a_count,
        coalesce(ua.total_post_score,0) as total_post_score,
        coalesce(ua.total_q_views,0) as total_q_views,
        ua.last_activity,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(ub.tag_badges,0) as tag_badges
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badges ub on ub.userid = ru.user_id
),
user_question_join as (
    select
        ue.*,
        qe.question_id,
        qe.question_date,
        qe.q_score,
        qe.q_views,
        qe.title,
        qe.tags,
        qe.q_up,
        qe.q_down,
        qe.q_fav,
        qe.answer_count,
        qe.max_answer_score,
        qe.avg_answer_score,
        qe.first_answer_date,
        qe.last_answer_date,
        qe.has_accepted,
        qe.first_closed_date,
        qe.last_closed_date,
        qe.close_events,
        qe.last_close_reason_id,
        qe.first_reopen_date,
        qe.reopen_events,
        qe.community_bumps,
        qe.hot_selected,
        qe.hot_removed
    from user_enriched ue
    left join question_enriched qe
      on qe.asker_id = ue.user_id
),
ranked_questions as (
    select
        uqj.*,
        row_number() over (partition by uqj.user_id order by coalesce(uqj.q_score, -2147483648) desc, uqj.q_views desc, uqj.question_date desc) as rn_score_desc,
        dense_rank() over (partition by uqj.user_id order by coalesce(uqj.answer_count, -1) desc) as dr_by_answers,
        avg(coalesce(uqj.q_score,0)) over (partition by uqj.user_id) as avg_user_q_score,
        sum(coalesce(uqj.q_views,0)) over (partition by uqj.user_id) as sum_user_q_views
    from user_question_join uqj
),
top_questions as (
    select *
    from ranked_questions
    where rn_score_desc <= 3
),
user_quality as (
    select
        rq.user_id,
        count(rq.question_id) as questions_total,
        sum(case when rq.has_accepted = 1 then 1 else 0 end) as accepted_qs,
        avg(case when rq.answer_count > 0 then 1.0 else 0.0 end) as answered_ratio,
        avg(coalesce(rq.avg_answer_score,0)) as avg_of_avg_answer_score,
        percentile_cont(0.5) within group (order by coalesce(rq.q_score,0)) as median_q_score
    from ranked_questions rq
    group by rq.user_id
),
tag_influence as (
    select
        tq.user_id,
        te.tag,
        count(distinct tq.question_id) as user_tag_qs,
        sum(coalesce(tq.q_views,0)) as user_tag_views
    from top_questions tq
    left join tag_expansion te on te.question_id = tq.question_id
    group by tq.user_id, te.tag
),
tag_influence_ranked as (
    select
        ti.*,
        row_number() over (partition by ti.user_id order by ti.user_tag_views desc, ti.user_tag_qs desc, coalesce(ti.tag,'~') asc) as tag_rank
    from tag_influence ti
),
best_tag as (
    select user_id,
           max(case when tag_rank = 1 then tag end) as top_tag,
           max(case when tag_rank = 1 then user_tag_qs end) as top_tag_qs,
           max(case when tag_rank = 1 then user_tag_views end) as top_tag_views
    from tag_influence_ranked
    group by user_id
),
dupes as (
    select
        dl.dup_post_id as question_id,
        dl.original_post_id,
        dl.dup_link_date
    from dup_links dl
),
dupe_flags as (
    select
        rq.user_id,
        count(distinct d.question_id) as dup_questions,
        count(distinct d.original_post_id) as unique_originals
    from ranked_questions rq
    left join dupes d on d.question_id = rq.question_id
    group by rq.user_id
),
recent_commenters as (
    select
        c.userid,
        count(*) filter (where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as comments_30d,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.userid
),
final_users as (
    select
        ue.user_id,
        ue.displayname,
        ue.reputation,
        ue.creationdate,
        ue.location,
        ue.websiteurl_norm,
        ue.signup_month,
        ue.q_count,
        ue.a_count,
        ue.total_post_score,
        ue.total_q_views,
        ue.last_activity,
        ue.gold_badges,
        ue.silver_badges,
        ue.bronze_badges,
        ue.tag_badges,
        uq.questions_total,
        uq.accepted_qs,
        uq.answered_ratio,
        uq.avg_of_avg_answer_score,
        uq.median_q_score,
        coalesce(df.dup_questions,0) as dup_questions,
        coalesce(df.unique_originals,0) as unique_originals,
        coalesce(rc.comments_30d,0) as comments_30d,
        rc.last_comment_date,
        bt.top_tag,
        bt.top_tag_qs,
        bt.top_tag_views
    from user_enriched ue
    left join user_quality uq on uq.user_id = ue.user_id
    left join dupe_flags df on df.user_id = ue.user_id
    left join recent_commenters rc on rc.userid = ue.user_id
    left join best_tag bt on bt.user_id = ue.user_id
),
scored as (
    select
        fu.*,
        (
            coalesce(fu.reputation,0) / nullif((select max(reputation) from users),0)
            + coalesce(fu.total_post_score,0) / nullif((select max(total_post_score) from user_activity),0)
            + least(coalesce(fu.total_q_views,0), 100000) / 100000
            + coalesce(fu.gold_badges*3 + fu.silver_badges*2 + fu.bronze_badges,0) / 50
            + coalesce(fu.accepted_qs,0) / nullif(nullif(fu.questions_total,0),0)
            + coalesce(fu.answered_ratio,0)
            - coalesce(fu.dup_questions,0) / 100
        ) as composite_score
    from final_users fu
),
scored_with_rank as (
    select
        s.*,
        row_number() over (
            order by s.composite_score desc, s.reputation desc, s.total_q_views desc, s.last_activity desc, s.user_id asc
        ) as overall_rank
    from scored s
)
select
    s.user_id,
    s.displayname,
    s.reputation,
    s.signup_month,
    s.q_count,
    s.a_count,
    s.questions_total,
    s.accepted_qs,
    round(cast(coalesce(s.answered_ratio,0) as numeric), 3) as answered_ratio,
    round(cast(coalesce(s.avg_of_avg_answer_score,0) as numeric), 2) as avg_of_avg_answer_score,
    s.median_q_score,
    s.dup_questions,
    s.unique_originals,
    s.top_tag,
    s.top_tag_qs,
    s.top_tag_views,
    s.total_post_score,
    s.total_q_views,
    s.gold_badges,
    s.silver_badges,
    s.bronze_badges,
    s.tag_badges,
    s.comments_30d,
    s.last_comment_date,
    s.last_activity,
    round(cast(s.composite_score as numeric), 4) as composite_score,
    case
        when s.top_tag is null then 'untagged-focus'
        when s.top_tag ~ '^[a-z0-9\-\.]+$' then 'clean'
        else 'mixed'
    end as tag_quality,
    case
        when s.last_activity is null then 'inactive'
        when s.last_activity < cast('2024-10-01 12:34:56' as timestamp) - interval '90 days' then 'stale'
        when s.last_activity < cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' then 'cool'
        else 'active'
    end as activity_bucket
from scored_with_rank s
where s.overall_rank <= 200
order by composite_score desc, reputation desc, total_q_views desc, user_id asc;