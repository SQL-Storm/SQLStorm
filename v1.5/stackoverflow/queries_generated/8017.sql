-- {"query": "8017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3364} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm,
           row_number() over (order by u.creationdate desc, u.id desc) as rn_global
    from users u
    where u.creationdate >= (select date_trunc('month', max(p.creationdate)) - interval '12 months' from posts p)
),
question_posts as (
    select p.id as post_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.favoritecount,
           p.closeddate,
           p.communityowneddate
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select p.id as post_id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score
    from posts p
    where p.posttypeid = 2
),
votes_by_type as (
    select v.postid,
           v.votetypeid,
           count(*) as vote_count,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_sum
    from votes v
    group by v.postid, v.votetypeid
),
agg_votes as (
    select postid,
           sum(case when votetypeid = 2 then vote_count else 0 end) as upvotes,
           sum(case when votetypeid = 3 then vote_count else 0 end) as downvotes,
           sum(case when votetypeid = 5 then vote_count else 0 end) as favorites,
           sum(bounty_sum) as bounty_total
    from votes_by_type
    group by postid
),
tag_explode as (
    select q.post_id,
           unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tagname
    from question_posts q
    where q.tags is not null and q.tags <> ''
),
tag_stats as (
    select te.post_id,
           count(*) as tag_count,
           max(case when lower(te.tagname) in ('sql','postgresql','mysql','tsql','sqlite') then 1 else 0 end) as is_db_related
    from tag_explode te
    group by te.post_id
),
post_history_flags as (
    select ph.postid,
           max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
           max(case when ph.posthistorytypeid in (11,13) then 1 else 0 end) as was_reopened_or_undeleted,
           max(case when ph.posthistorytypeid in (19) then 1 else 0 end) as was_protected,
           max(case when ph.posthistorytypeid in (52) then 1 else 0 end) as was_hot
    from posthistory ph
    group by ph.postid
),
comment_summary as (
    select c.postid,
           count(*) as comment_count,
           max(c.creationdate) as last_comment_at,
           sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
           sum(case when c.score < 0 then 1 else 0 end) as neg_comments
    from comments c
    group by c.postid
),
linked_duplicates as (
    select pl.postid as duplicate_of,
           count(*) filter (where pl.linktypeid = 3) as dup_links,
           count(*) filter (where pl.linktypeid = 1) as related_links
    from postlinks pl
    group by pl.postid
),
user_badge_summary as (
    select b.userid,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
question_metrics as (
    select q.post_id,
           q.user_id,
           q.creationdate,
           q.score,
           q.viewcount,
           q.title,
           coalesce(q.answercount, 0) as answercount,
           coalesce(av.upvotes, 0) as upvotes,
           coalesce(av.downvotes, 0) as downvotes,
           coalesce(av.favorites, 0) as favorites,
           coalesce(av.bounty_total, 0) as bounty_total,
           coalesce(cs.comment_count, 0) as comment_count,
           cs.last_comment_at,
           coalesce(ls.dup_links, 0) as dup_links,
           coalesce(ls.related_links, 0) as related_links,
           coalesce(ts.tag_count, 0) as tag_count,
           coalesce(ts.is_db_related, 0) as is_db_related,
           coalesce(phf.was_closed_or_migrated, 0) as was_closed_or_migrated,
           coalesce(phf.was_reopened_or_undeleted, 0) as was_reopened_or_undeleted,
           coalesce(phf.was_protected, 0) as was_protected,
           coalesce(phf.was_hot, 0) as was_hot,
           case
             when q.closeddate is not null then 1
             when coalesce(phf.was_closed_or_migrated,0) = 1 then 1
             else 0
           end as is_closed_any,
           case when q.communityowneddate is not null then 1 else 0 end as is_community_owned
    from question_posts q
    left join agg_votes av on av.postid = q.post_id
    left join comment_summary cs on cs.postid = q.post_id
    left join linked_duplicates ls on ls.duplicate_of = q.post_id
    left join tag_stats ts on ts.post_id = q.post_id
    left join post_history_flags phf on phf.postid = q.post_id
),
user_activity as (
    select u.id as user_id,
           count(*) filter (where p.posttypeid = 1) as questions,
           count(*) filter (where p.posttypeid = 2) as answers,
           max(p.creationdate) as last_post_at,
           sum(coalesce(p.score,0)) as total_post_score
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
answer_latency as (
    select a.question_id,
           min(a.creationdate) as first_answer_at,
           avg(extract(epoch from (a.creationdate - q.creationdate))) as avg_seconds_to_answer
    from answer_posts a
    join question_posts q on q.post_id = a.question_id
    group by a.question_id
),
ranked_questions as (
    select qm.*,
           coalesce(al.first_answer_at, null) as first_answer_at,
           coalesce(al.avg_seconds_to_answer, null) as avg_seconds_to_answer,
           -- composite ranking metric mixing engagement and quality
           (
             0.40 * coalesce(qm.upvotes - qm.downvotes, 0) +
             0.25 * coalesce(qm.viewcount, 0) / nullif(1 + ln(1 + qm.viewcount), 0) +
             0.15 * coalesce(qm.comment_count, 0) +
             0.10 * coalesce(qm.favorites, 0) +
             0.10 * case when qm.is_db_related = 1 then 10 else 0 end
           ) as engagement_score,
           row_number() over (partition by qm.is_db_related order by qm.score desc, qm.viewcount desc, qm.post_id) as rn_by_topic,
           percent_rank() over (order by coalesce(qm.upvotes - qm.downvotes,0) desc nulls last) as pr_net_votes,
           ntile(20) over (order by coalesce(qm.viewcount,0) desc nulls last) as view_ntile20
    from question_metrics qm
    left join answer_latency al on al.question_id = qm.post_id
),
user_enriched as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.creationdate,
           ru.location,
           ru.websiteurl_norm,
           ru.rn_global,
           ua.questions,
           ua.answers,
           ua.last_post_at,
           ua.total_post_score,
           ubs.gold_badges,
           ubs.silver_badges,
           ubs.bronze_badges,
           ubs.tag_badges
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badge_summary ubs on ubs.userid = ru.user_id
),
user_q_agg as (
    select rq.user_id,
           count(*) as q_count,
           sum(case when rq.is_db_related = 1 then 1 else 0 end) as db_q_count,
           avg(coalesce(rq.upvotes - rq.downvotes,0)) as avg_net_votes,
           max(rq.viewcount) as max_views,
           sum(rq.favorites) as sum_favorites,
           sum(rq.comment_count) as sum_comments,
           sum(case when rq.is_closed_any = 1 then 1 else 0 end) as closed_q,
           sum(coalesce(rq.bounty_total,0)) as bounty_sum
    from ranked_questions rq
    group by rq.user_id
),
user_quality as (
    select ue.*,
           coalesce(uqa.q_count, 0) as q_count,
           coalesce(uqa.db_q_count, 0) as db_q_count,
           coalesce(uqa.avg_net_votes, 0) as avg_q_net_votes,
           coalesce(uqa.max_views, 0) as max_q_views,
           coalesce(uqa.sum_favorites, 0) as sum_q_favorites,
           coalesce(uqa.sum_comments, 0) as sum_q_comments,
           coalesce(uqa.closed_q, 0) as closed_q,
           coalesce(uqa.bounty_sum, 0) as bounty_sum
    from user_enriched ue
    left join user_q_agg uqa on uqa.user_id = ue.user_id
),
topk_questions as (
    select rq.*
    from ranked_questions rq
    where rq.rn_by_topic <= 100
),
cross_user_topq as (
    select uq.user_id,
           rq.post_id,
           rq.title,
           rq.viewcount,
           rq.score,
           rq.engagement_score,
           rq.is_db_related,
           rq.rn_by_topic,
           rq.pr_net_votes
    from user_quality uq
    join topk_questions rq
      on rq.user_id = uq.user_id
),
db_related_rollup as (
    select
      is_db_related,
      count(*) as cnt,
      avg(engagement_score) as avg_eng,
      sum(case when pr_net_votes >= 0.9 then 1 else 0 end) as top10p_netvote,
      min(rn_by_topic) as best_rank
    from cross_user_topq
    group by is_db_related
),
time_buckets as (
    select
      date_trunc('month', qm.creationdate) as month,
      count(*) as q_cnt,
      avg(qm.score) as avg_score,
      avg(coalesce(al.avg_seconds_to_answer,0)) as avg_secs_to_answer
    from question_metrics qm
    left join answer_latency al on al.question_id = qm.post_id
    group by date_trunc('month', qm.creationdate)
),
final_scores as (
    select uq.user_id,
           uq.displayname,
           uq.reputation,
           uq.questions,
           uq.answers,
           uq.gold_badges,
           uq.silver_badges,
           uq.bronze_badges,
           uq.tag_badges,
           uq.q_count,
           uq.db_q_count,
           uq.avg_q_net_votes,
           uq.max_q_views,
           uq.sum_q_favorites,
           uq.sum_q_comments,
           uq.closed_q,
           uq.bounty_sum,
           -- composite score per user with NULL-safe normalization
           (
             0.30 * ln(1 + greatest(uq.reputation,0)) +
             0.20 * coalesce(uq.avg_q_net_votes,0) +
             0.15 * ln(1 + greatest(uq.max_q_views,0)) +
             0.10 * ln(1 + greatest(uq.sum_q_favorites,0)) +
             0.10 * ln(1 + greatest(uq.sum_q_comments,0)) +
             0.10 * (coalesce(uq.gold_badges,0) * 3 + coalesce(uq.silver_badges,0) * 2 + coalesce(uq.bronze_badges,0)) -
             0.05 * coalesce(uq.closed_q,0)
           ) as author_quality_score
    from user_quality uq
),
dense_ranked as (
    select fs.*,
           dense_rank() over (order by fs.author_quality_score desc, fs.reputation desc) as dr_author
    from final_scores fs
),
unioned_showcase as (
    select
      'USER' as entity,
      cast(dr.user_id as text) as entity_id,
      dr.displayname as label,
      dr.author_quality_score as score1,
      dr.reputation as score2,
      null::int as score3,
      null::text as extra_json
    from dense_ranked dr
    where dr.dr_author <= 200
    union all
    select
      'QUESTION' as entity,
      cast(rq.post_id as text) as entity_id,
      coalesce(substring(rq.title from 1 for 120), '(no title)') as label,
      rq.engagement_score as score1,
      rq.viewcount as score2,
      rq.score as score3,
      concat('{"db_related":', rq.is_db_related, ',"pr":', round(100*rq.pr_net_votes)::int, '}') as extra_json
    from ranked_questions rq
    where rq.view_ntile20 in (1,2,3,4) -- top 20% by views
)
select s.*
from unioned_showcase s
left join (
    select 'USER' as entity, cast(user_id as text) as entity_id, max(creationdate) as max_created
    from recent_users
    group by user_id
    union all
    select 'QUESTION' as entity, cast(post_id as text) as entity_id, max(creationdate)
    from question_posts
    group by post_id
) t on t.entity = s.entity and t.entity_id = s.entity_id
where (
    s.entity = 'USER'
    and exists (
        select 1
        from posts p
        where p.owneruserid::text = s.entity_id
          and p.posttypeid in (1,2)
          and p.creationdate > now() - interval '365 days'
    )
)
or (
    s.entity = 'QUESTION'
    and not exists (
        select 1
        from postlinks pl
        where pl.postid::text = s.entity_id
          and pl.linktypeid = 3
    )
)
order by s.entity asc, s.score1 desc nulls last, s.score2 desc nulls last, s.score3 desc nulls last, s.entity_id
limit 1000;