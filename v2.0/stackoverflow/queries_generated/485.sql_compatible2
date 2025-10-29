with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        case when lower(coalesce(u.location,'')) like '%remote%' or lower(coalesce(u.location,'')) like '%anywhere%' then 1 else 0 end as is_remoteish
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        avg(nullif(p.viewcount,0)) as avg_views_nonzero,
        max(p.lastactivitydate) as last_activity,
        count(*) filter (where p.closeddate is not null) as closed_posts,
        count(distinct p.tags) filter (where p.posttypeid = 1 and p.tags is not null) as distinct_tag_sets,
        count(*) filter (where p.communityowneddate is not null) as community_owned_cnt
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
vote_summaries as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
accepted_answers as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.acceptedanswerid,
        a.owneruserid as answerer_id,
        a.score as accepted_answer_score
    from posts q
    left join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
),
tag_exploded as (
    select
        p.id as post_id,
        lower(trim(t.tag)) as tag
    from posts p
    cross join lateral (
        select unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
    ) t
    where p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
),
tag_popularity as (
    select
        te.tag,
        count(*) as tag_q_count,
        avg(coalesce(p.score,0)) as avg_tag_score
    from tag_exploded te
    join posts p on p.id = te.post_id
    group by te.tag
),
comment_insights as (
    select
        c.userid as user_id,
        count(*) as comments_count,
        sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_commented_at
    from comments c
    where c.userid is not null
    group by c.userid
),
edits_and_history as (
    select
        ph.userid as user_id,
        count(*) as edit_events,
        sum(case when ph.posthistorytypeid in (4,5,6,7,8,9,24) then 1 else 0 end) as content_edit_events,
        sum(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36,50,52,53) then 1 else 0 end) as mod_state_events,
        min(ph.creationdate) as first_event,
        max(ph.creationdate) as last_event
    from posthistory ph
    where ph.userid is not null
    group by ph.userid
),
dupe_clusters as (
    select
        pl.relatedpostid as canonical_id,
        count(*) filter (where pl.linktypeid = 3) as dup_count,
        min(pl.creationdate) as first_linked,
        max(pl.creationdate) as last_linked
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.relatedpostid
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when coalesce(b.tagbased, false) = true then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
questions_with_metrics as (
    select
        p.id as post_id,
        p.owneruserid as owner_id,
        p.score,
        coalesce(vs.upvotes,0) as upvotes,
        coalesce(vs.downvotes,0) as downvotes,
        coalesce(vs.favorites,0) as favorites,
        coalesce(vs.bounty_total,0) as bounty_total,
        coalesce(aa.acceptedanswerid,0) as accepted_answer_id,
        aa.answerer_id,
        aa.accepted_answer_score,
        dc.dup_count
    from posts p
    left join vote_summaries vs on vs.postid = p.id
    left join accepted_answers aa on aa.question_id = p.id
    left join dupe_clusters dc on dc.canonical_id = p.id
    where p.posttypeid = 1
),
user_quality as (
    select
        qwm.owner_id as user_id,
        count(*) as questions_asked,
        sum(case when qwm.accepted_answer_id is not null and qwm.accepted_answer_id <> 0 then 1 else 0 end) as accepted_got,
        avg(qwm.score) as avg_q_score,
        percentile_cont(0.5) within group (order by qwm.score) as median_q_score,
        avg(qwm.upvotes - qwm.downvotes) as avg_net_votes,
        sum(qwm.favorites) as total_favorites_on_q,
        sum(qwm.bounty_total) as total_bounty_in,
        sum(coalesce(qwm.dup_count,0)) as total_dup_marked_against
    from questions_with_metrics qwm
    group by qwm.owner_id
),
answer_metrics as (
    select
        p.owneruserid as user_id,
        count(*) as answers_posted,
        sum(case when p.score > 0 then 1 else 0 end) as pos_answers,
        avg(p.score) as avg_answer_score,
        percentile_disc(0.9) within group (order by p.score) as p90_answer_score
    from posts p
    where p.posttypeid = 2
    group by p.owneruserid
),
user_ranked as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl_norm,
        ua.q_count,
        ua.a_count,
        ua.total_post_score,
        ua.avg_views_nonzero,
        ua.last_activity,
        ua.closed_posts,
        ua.distinct_tag_sets,
        ua.community_owned_cnt,
        coalesce(ci.comments_count,0) as comments_count,
        coalesce(ci.positive_comments,0) as positive_comments,
        ci.avg_comment_score,
        ci.last_commented_at,
        coalesce(eh.edit_events,0) as edit_events,
        coalesce(eh.content_edit_events,0) as content_edit_events,
        coalesce(eh.mod_state_events,0) as mod_state_events,
        eh.first_event,
        eh.last_event,
        coalesce(ub.total_badges,0) as total_badges,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(ub.tag_badges,0) as tag_badges,
        coalesce(uq.questions_asked,0) as questions_asked,
        coalesce(uq.accepted_got,0) as accepted_got,
        uq.avg_q_score,
        uq.median_q_score,
        uq.avg_net_votes,
        coalesce(uq.total_favorites_on_q,0) as total_favorites_on_q,
        coalesce(uq.total_bounty_in,0) as total_bounty_in,
        coalesce(uq.total_dup_marked_against,0) as total_dup_marked_against,
        coalesce(am.answers_posted,0) as answers_posted,
        coalesce(am.pos_answers,0) as pos_answers,
        am.avg_answer_score,
        am.p90_answer_score,
        ru.is_remoteish
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_insights ci on ci.user_id = ru.user_id
    left join edits_and_history eh on eh.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
    left join answer_metrics am on am.user_id = ru.user_id
),
scored as (
    select
        ur.*,
        case
            when coalesce(ur.answers_posted,0) = 0 and coalesce(ur.questions_asked,0) = 0 then 0
            else
                0.35 * coalesce(ur.avg_answer_score, 0)
              + 0.30 * coalesce(ur.avg_q_score, 0)
              + 0.15 * coalesce(ur.avg_net_votes, 0)
              + 0.10 * ln(1 + coalesce(ur.total_badges,0))
              + 0.05 * ln(1 + coalesce(ur.comments_count,0))
              + 0.05 * least(5, coalesce(ur.p90_answer_score,0))
        end as quality_score,
        dense_rank() over (order by
            coalesce(0.35 * coalesce(ur.avg_answer_score,0)
                   + 0.30 * coalesce(ur.avg_q_score,0)
                   + 0.15 * coalesce(ur.avg_net_votes,0)
                   + 0.10 * ln(1 + coalesce(ur.total_badges,0))
                   + 0.05 * ln(1 + coalesce(ur.comments_count,0))
                   + 0.05 * least(5, coalesce(ur.p90_answer_score,0)), 0) desc,
            ur.reputation desc,
            ur.user_id
        ) as rk_desc
    from user_ranked ur
),
top_tags as (
    select
        te.tag,
        count(*) as cnt,
        avg(p.score) as avg_score_for_tag,
        max(p.viewcount) as max_views_for_tag
    from tag_exploded te
    join posts p on p.id = te.post_id
    group by te.tag
    having count(*) > 10
),
user_top_tag as (
    select
        p.owneruserid as user_id,
        te.tag,
        row_number() over (partition by p.owneruserid order by count(*) desc, avg(p.score) desc) as rn
    from posts p
    join tag_exploded te on te.post_id = p.id
    group by p.owneruserid, te.tag
),
final_enriched as (
    select
        s.*,
        tpop.tag_q_count as global_tag_q_count,
        tpop.avg_tag_score as global_avg_tag_score,
        utt.tag as user_primary_tag
    from scored s
    left join user_top_tag utt on utt.user_id = s.user_id and utt.rn = 1
    left join tag_popularity tpop on tpop.tag = utt.tag
)
select
    fe.user_id,
    fe.displayname,
    fe.reputation,
    fe.creationdate,
    fe.location,
    fe.websiteurl_norm,
    fe.q_count,
    fe.a_count,
    fe.questions_asked,
    fe.answers_posted,
    fe.accepted_got,
    fe.avg_q_score,
    fe.median_q_score,
    fe.avg_answer_score,
    fe.p90_answer_score,
    fe.avg_net_votes,
    fe.total_favorites_on_q,
    fe.total_bounty_in,
    fe.total_dup_marked_against,
    fe.comments_count,
    fe.positive_comments,
    fe.avg_comment_score,
    fe.edit_events,
    fe.content_edit_events,
    fe.mod_state_events,
    fe.total_badges,
    fe.gold_badges,
    fe.silver_badges,
    fe.bronze_badges,
    fe.tag_badges,
    fe.distinct_tag_sets,
    fe.closed_posts,
    fe.community_owned_cnt,
    fe.last_activity,
    fe.last_commented_at,
    fe.first_event,
    fe.last_event,
    fe.quality_score,
    fe.rk_desc as rank_overall,
    fe.user_primary_tag,
    coalesce(fe.global_tag_q_count,0) as global_tag_q_count,
    fe.global_avg_tag_score,
    case
        when fe.is_remoteish = 1 and fe.quality_score > (
            select avg(quality_score) from (select quality_score from scored) z
        ) then 'remote-high-perf'
        when fe.quality_score is null then 'insufficient'
        when fe.quality_score >= (
            select percentile_cont(0.9) within group (order by quality_score) from (select quality_score from scored) z
        ) then 'p90'
        when fe.quality_score >= (
            select percentile_cont(0.5) within group (order by quality_score) from (select quality_score from scored) z
        ) then 'p50-90'
        else 'below-median'
    end as perf_bucket
from final_enriched fe
where
    (fe.reputation > 1000 or fe.total_badges >= 10 or fe.quality_score > 5)
    and not (fe.user_primary_tag is null and fe.avg_answer_score is null and fe.avg_q_score is null)
order by fe.rk_desc, fe.user_id
limit 200;