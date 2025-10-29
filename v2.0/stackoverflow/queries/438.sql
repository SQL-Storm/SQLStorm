-- {"query": "438.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2601}
with recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.owneruserid as owneruserid,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.parentid,
    p.lastactivitydate,
    coalesce(nullif(trim(p.ownerdisplayname), ''), u.displayname, 'Anonymous') as owner_displayname,
    u.reputation,
    u.upvotes,
    u.downvotes
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
tag_expanded as (
  select
    rp.*,
    unnest(string_to_array(substring(rp.tags, 2, length(rp.tags)-2), '><')) as tagname
  from recent_posts rp
  where rp.posttypeid = 1
),
comment_stats as (
  select
    c.postid,
    count(*) as comment_count,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) as total_votes,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
post_history_flags as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
    max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
    max(case when ph.posthistorytypeid in (12,14) then 1 else 0 end) as was_deleted_or_locked,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_events,
    min(ph.creationdate) as first_history_at,
    max(ph.creationdate) as last_history_at
  from posthistory ph
  group by ph.postid
),
linked_dupes as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links,
    max(pl.creationdate) as last_link_at
  from postlinks pl
  group by pl.postid
),
user_badge_scores as (
  select
    b.userid,
    sum(case b.class when 1 then 10 when 2 then 3 when 3 then 1 else 0 end) as badge_score,
    count(*) filter (where b.tagbased = true) as tag_badges,
    count(*) filter (where b.tagbased = false) as named_badges,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
question_answer_stats as (
  select
    q.id as question_id,
    count(a.id) as answer_count,
    sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
    max(a.score) as max_answer_score,
    avg(a.score) as avg_answer_score,
    max(a.creationdate) as last_answer_at,
    count(*) filter (where a.id = q.acceptedanswerid) as has_accepted
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id
),
tag_density as (
  select
    te.tagname,
    count(*) as q_count,
    sum(te.viewcount) as total_views,
    avg(te.score) as avg_q_score,
    percentile_cont(0.9) within group (order by te.viewcount) as p90_views
  from tag_expanded te
  group by te.tagname
),
-- compute global median of viewcount separately (dialect compatible)
global_view_median as (
  select percentile_cont(0.5) within group (order by viewcount) as median_views_global
  from tag_expanded
),
ranked_questions as (
  select
    te.id,
    te.title,
    te.owner_displayname,
    te.reputation,
    te.creationdate,
    te.viewcount,
    te.score,
    te.tags,
    te.tagname,
    qa.answer_count,
    qa.has_accepted,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.bounty_total,0) as bounty_total,
    coalesce(cs.comment_count,0) as comment_count,
    coalesce(ph.was_closed_or_migrated,0) as was_closed_or_migrated,
    coalesce(ld.duplicate_links,0) as duplicate_links,
    coalesce(ub.badge_score,0) as user_badge_score,
    td.q_count as tag_q_count,
    td.avg_q_score as tag_avg_q_score,
    td.p90_views as tag_p90_views,
    row_number() over (partition by te.id order by te.creationdate desc) as rn_last_by_id,
    dense_rank() over (order by coalesce(va.upvotes,0) - coalesce(va.downvotes,0) desc, te.viewcount desc) as dr_engagement,
    gv.median_views_global,
    te.owneruserid
  from tag_expanded te
  left join question_answer_stats qa on qa.question_id = te.id
  left join vote_agg va on va.postid = te.id
  left join comment_stats cs on cs.postid = te.id
  left join post_history_flags ph on ph.postid = te.id
  left join linked_dupes ld on ld.postid = te.id
  left join user_badge_scores ub on ub.userid = te.owneruserid
  left join tag_density td on td.tagname = te.tagname
  cross join global_view_median gv
),
outlier_detection as (
  select
    rq.*,
    case
      when rq.viewcount >= greatest(rq.tag_p90_views, rq.median_views_global) then 1
      when rq.viewcount is null or rq.tag_p90_views is null then null
      else 0
    end as is_view_outlier,
    case
      when rq.score >= 2 * coalesce(rq.tag_avg_q_score, 0) and rq.score >= 5 then 1 else 0
    end as is_score_outlier
  from ranked_questions rq
),
aggregated_by_question as (
  select
    id,
    min(title) as title,
    min(owner_displayname) as owner_displayname,
    min(reputation) as owner_reputation,
    min(creationdate) as creationdate,
    max(viewcount) as viewcount,
    max(score) as score,
    string_agg(distinct tagname, ',') as tags_flat,
    max(answer_count) as answer_count,
    max(has_accepted) as has_accepted,
    max(upvotes) as upvotes,
    max(downvotes) as downvotes,
    max(bounty_total) as bounty_total,
    max(comment_count) as comment_count,
    max(was_closed_or_migrated) as was_closed_or_migrated,
    max(duplicate_links) as duplicate_links,
    max(user_badge_score) as user_badge_score,
    max(tag_q_count) as tag_q_count,
    max(tag_avg_q_score) as tag_avg_q_score,
    max(tag_p90_views) as tag_p90_views,
    max(dr_engagement) as dr_engagement,
    max(median_views_global) as median_views_global,
    max(case when is_view_outlier = 1 then 1 else 0 end) as any_view_outlier,
    max(case when is_score_outlier = 1 then 1 else 0 end) as any_score_outlier
  from outlier_detection
  where rn_last_by_id = 1
  group by id
),
bench_union as (
  select
    aq.id,
    aq.title,
    aq.owner_displayname,
    aq.owner_reputation,
    aq.creationdate,
    aq.viewcount,
    aq.score,
    aq.tags_flat,
    aq.answer_count,
    aq.has_accepted,
    aq.upvotes,
    aq.downvotes,
    aq.bounty_total,
    aq.comment_count,
    aq.was_closed_or_migrated,
    aq.duplicate_links,
    aq.user_badge_score,
    aq.tag_q_count,
    aq.tag_avg_q_score,
    aq.tag_p90_views,
    aq.dr_engagement,
    aq.median_views_global,
    aq.any_view_outlier,
    aq.any_score_outlier,
    'A' as source
  from aggregated_by_question aq
  where aq.viewcount > 0

  union all

  select
    aq.id,
    aq.title,
    aq.owner_displayname,
    aq.owner_reputation,
    aq.creationdate,
    aq.viewcount,
    aq.score,
    aq.tags_flat,
    aq.answer_count,
    aq.has_accepted,
    aq.upvotes,
    aq.downvotes,
    aq.bounty_total,
    aq.comment_count,
    aq.was_closed_or_migrated,
    aq.duplicate_links,
    aq.user_badge_score,
    aq.tag_q_count,
    aq.tag_avg_q_score,
    aq.tag_p90_views,
    aq.dr_engagement,
    aq.median_views_global,
    aq.any_view_outlier,
    aq.any_score_outlier,
    'B' as source
  from aggregated_by_question aq
  where coalesce(aq.upvotes - aq.downvotes, 0) >= 0
),
final_rank as (
  select
    bu.*,
    (coalesce(bu.upvotes,0) - coalesce(bu.downvotes,0)) / nullif(cast(bu.viewcount as numeric),0) as uv_ratio,
    (coalesce(bu.score,0) + coalesce(bu.answer_count,0) + coalesce(bu.comment_count,0)) as activity_score,
    case
      when bu.was_closed_or_migrated = 1 and coalesce(bu.duplicate_links,0) > 0 then 'Closed/Dupe'
      when bu.was_closed_or_migrated = 1 then 'Closed'
      when coalesce(bu.duplicate_links,0) > 0 then 'Possible Dupe'
      else 'Open'
    end as status_label,
    rank() over (order by
      (coalesce(bu.upvotes,0) - coalesce(bu.downvotes,0)) desc,
      coalesce(bu.viewcount,0) desc,
      coalesce(bu.bounty_total,0) desc,
      coalesce(bu.answer_count,0) desc
    ) as overall_rank
  from bench_union bu
)
select
  fr.id,
  fr.title,
  fr.owner_displayname,
  fr.owner_reputation,
  fr.creationdate,
  fr.viewcount,
  fr.score,
  fr.tags_flat,
  fr.answer_count,
  fr.has_accepted,
  fr.upvotes,
  fr.downvotes,
  fr.bounty_total,
  fr.comment_count,
  fr.status_label,
  fr.user_badge_score,
  fr.tag_q_count,
  fr.tag_avg_q_score,
  fr.tag_p90_views,
  fr.any_view_outlier,
  fr.any_score_outlier,
  fr.uv_ratio,
  fr.activity_score,
  fr.overall_rank,
  fr.source
from final_rank fr
where
  (fr.any_view_outlier = 1 or fr.any_score_outlier = 1 or fr.bounty_total > 0)
  and fr.overall_rank <= 500
order by fr.overall_rank, fr.id;