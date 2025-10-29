-- {"query": "851.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3975}
with
-- active users with derived metrics
active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.location,
    coalesce(nullif(trim(lower(u.websiteurl)), ''), 'n/a') as website_norm,
    extract(epoch from (u.lastaccessdate - u.creationdate)) / 86400.0 as active_days,
    cast((u.upvotes - coalesce(u.downvotes,0)) as integer) as net_votes,
    row_number() over (order by u.reputation desc, u.id) as rn_rep
  from users u
  where u.reputation > 0
),
-- questions with parsed tags and engagement metrics
q_posts as (
  select
    p.id as question_id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.title,
    p.tags,
    string_to_array(substring(p.tags from 2 for greatest(length(p.tags)-2,0)), '><') as tag_arr,
    coalesce(p.favoritecount, 0) as favs,
    case when p.closeddate is null then 0 else 1 end as is_closed
  from posts p
  where p.posttypeid = 1
),
-- answers mapped to their parent question
a_posts as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answer_user_id,
    a.creationdate as answer_creation,
    a.score as answer_score
  from posts a
  where a.posttypeid = 2
),
-- votes aggregated per post with window distributions
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    count(*) as total_votes,
    percentile_disc(0.5) within group (order by v.votetypeid) as vote_type_median
  from votes v
  group by v.postid
),
-- comments density per question
comment_agg as (
  select
    c.postid,
    count(*) as comment_count,
    avg(c.score) as avg_comment_score,
    min(c.creationdate) as first_comment_at,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
-- post history signals
ph_signals as (
  select
    ph.postid,
    sum(case when ph.posthistorytypeid in (4,5,6) then 1 else 0 end) as edits,
    sum(case when ph.posthistorytypeid in (10) then 1 else 0 end) as closes,
    sum(case when ph.posthistorytypeid in (11) then 1 else 0 end) as reopens,
    sum(case when ph.posthistorytypeid in (12) then 1 else 0 end) as deletions,
    sum(case when ph.posthistorytypeid in (13) then 1 else 0 end) as undeletions,
    max(ph.creationdate) as last_history_at
  from posthistory ph
  group by ph.postid
),
-- tag popularity for tags attached to questions
tag_pop as (
  select
    t.tagname,
    t.count as tag_count
  from tags t
),
-- link graph around questions (duplicates and related)
link_graph as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count
  from postlinks pl
  group by pl.postid
),
-- answers quality per question
answer_stats as (
  select
    ap.question_id,
    count(*) as answers_total,
    sum(case when ap.answer_score > 0 then 1 else 0 end) as pos_answers,
    max(ap.answer_score) as max_answer_score,
    min(ap.answer_creation) as first_answer_at,
    max(ap.answer_creation) as last_answer_at,
    avg(ap.answer_score) as avg_answer_score
  from a_posts ap
  group by ap.question_id
),
-- per-user badge snapshot
user_badges as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when cast(b.tagbased as integer) = 1 then 1 else 0 end) as tag_badges,
    count(*) as badge_total,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
-- question-level tag enrichment (explode)
q_tags as (
  select
    q.question_id,
    trim(unnest(q.tag_arr)) as tagname
  from q_posts q
),
-- top tag by global popularity per question
q_top_tag as (
  select qt.question_id,
         qt.tagname,
         tp.tag_count,
         row_number() over (partition by qt.question_id order by tp.tag_count desc nulls last, qt.tagname) as rn_tag
  from q_tags qt
  left join tag_pop tp on lower(tp.tagname) = lower(qt.tagname)
),
-- compute activity windows for questions
q_activity as (
  select
    q.question_id,
    q.creationdate,
    coalesce(ca.first_comment_at, q.creationdate) as first_interaction_at,
    coalesce(ans.first_answer_at, q.creationdate) as first_answer_at,
    greatest(coalesce(ca.last_comment_at, q.creationdate), coalesce(ans.last_answer_at, q.creationdate)) as last_interaction_at
  from q_posts q
  left join comment_agg ca on ca.postid = q.question_id
  left join answer_stats ans on ans.question_id = q.question_id
),
-- dense stats rollup per question
q_rollup as (
  select
    q.question_id,
    q.owneruserid as owner_user_id,
    q.title,
    q.score as q_score,
    q.viewcount as q_views,
    q.answercount as q_answercount,
    q.favs as q_favs,
    q.is_closed,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.total_votes,0) as total_votes,
    coalesce(va.bounty_started,0) as bounty_started,
    coalesce(va.bounty_awarded,0) as bounty_awarded,
    coalesce(la.linked_count,0) as linked_count,
    coalesce(la.duplicate_count,0) as duplicate_count,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(ca.avg_comment_score,0) as avg_comment_score,
    coalesce(ph.edits,0) as edits,
    coalesce(ph.closes,0) as closes,
    coalesce(ph.reopens,0) as reopens,
    coalesce(ph.deletions,0) as deletions,
    coalesce(ph.undeletions,0) as undeletions,
    qa.first_interaction_at,
    qa.first_answer_at,
    qa.last_interaction_at
  from q_posts q
  left join vote_agg va on va.postid = q.question_id
  left join link_graph la on la.postid = q.question_id
  left join comment_agg ca on ca.postid = q.question_id
  left join ph_signals ph on ph.postid = q.question_id
  left join q_activity qa on qa.question_id = q.question_id
),
-- per-user aggregates over their questions
owner_agg as (
  select
    qr.owner_user_id as user_id,
    count(*) as q_count,
    avg(qr.q_score) as avg_q_score,
    avg(qr.q_views) as avg_q_views,
    sum(qr.q_favs) as total_favs,
    sum(qr.duplicate_count) as total_dups_linked,
    sum(case when qr.is_closed = 1 then 1 else 0 end) as closed_questions,
    percentile_disc(0.9) within group (order by qr.q_views) as p90_views
  from q_rollup qr
  where qr.owner_user_id is not null
  group by qr.owner_user_id
),
-- compute a per-question complexity score
q_scorecard as (
  select
    qr.*,
    coalesce(1.0 * q_score + 0.2 * q_views + 2.0 * upvotes - 1.5 * downvotes + 5.0 * bounty_awarded / nullif(total_votes,0), 0) as engagement_score,
    case when comment_count > 0 then cast(q_views as numeric) / comment_count else null end as views_per_comment,
    case when q_answercount > 0 then cast((upvotes - downvotes) as numeric) / q_answercount else null end as net_per_answer,
    extract(epoch from (last_interaction_at - first_interaction_at)) / 3600.0 as interaction_span_hours
  from q_rollup qr
),
-- rank questions per user by engagement
ranked_q as (
  select
    qs.*,
    row_number() over (partition by qs.owner_user_id order by qs.engagement_score desc nulls last, qs.q_views desc, qs.question_id) as rn_engagement,
    rank() over (order by qs.engagement_score desc nulls last) as global_rank
  from q_scorecard qs
),
-- select the most popular tag per question
q_best_tag as (
  select question_id, tagname as top_tag, tag_count
  from q_top_tag
  where rn_tag = 1
),
-- join with users and badges
enriched as (
  select
    rq.question_id,
    rq.title,
    rq.owner_user_id,
    au.displayname,
    au.reputation,
    ua.badge_total,
    coalesce(ua.gold_badges,0) as gold_badges,
    coalesce(ua.silver_badges,0) as silver_badges,
    coalesce(ua.bronze_badges,0) as bronze_badges,
    oa.q_count as user_q_count,
    oa.avg_q_score,
    oa.avg_q_views,
    oa.total_favs as user_total_favs,
    oa.closed_questions,
    rq.q_score,
    rq.q_views,
    rq.q_answercount,
    rq.upvotes,
    rq.downvotes,
    rq.total_votes,
    rq.comment_count,
    rq.edits,
    rq.closes,
    rq.reopens,
    rq.duplicate_count,
    rq.engagement_score,
    rq.views_per_comment,
    rq.net_per_answer,
    rq.interaction_span_hours,
    rq.global_rank,
    qb.top_tag,
    qb.tag_count as top_tag_count,
    au.website_norm,
    au.active_days,
    au.net_votes as user_net_votes
  from ranked_q rq
  left join active_users au on au.user_id = rq.owner_user_id
  left join user_badges ua on ua.userid = rq.owner_user_id
  left join owner_agg oa on oa.user_id = rq.owner_user_id
  left join q_best_tag qb on qb.question_id = rq.question_id
  where rq.rn_engagement <= 3
),
-- compute cohorts based on user reputation and activity
cohorts as (
  select
    e.*,
    case
      when e.reputation >= 100000 then 'legend'
      when e.reputation >= 20000 then 'expert'
      when e.reputation >= 5000 then 'pro'
      when e.reputation >= 1000 then 'intermediate'
      else 'novice'
    end as rep_band,
    case
      when e.active_days >= 3650 then 'veteran'
      when e.active_days >= 1825 then 'longtime'
      when e.active_days >= 365 then 'yearling'
      else 'newcomer'
    end as tenure_band
  from enriched e
),
-- correlated subquery to get accepted answer score if exists
accepted_answer as (
  select
    q.id as question_id,
    (select p2.score from posts p2 where p2.id = q.acceptedanswerid) as accepted_answer_score
  from posts q
  where q.posttypeid = 1 and q.acceptedanswerid is not null
),
-- final assembly with set operations to ensure inclusion of certain edge cases
final_union as (
  select c.*, aa.accepted_answer_score
  from cohorts c
  left join accepted_answer aa on aa.question_id = c.question_id

  union all

  -- include high-duplicate questions even if not top-3 for their user
  select
    c2.*, aa2.accepted_answer_score
  from (
    select
      qs.question_id,
      qs.title,
      qs.owner_user_id,
      au.displayname,
      au.reputation,
      ua.badge_total,
      coalesce(ua.gold_badges,0) as gold_badges,
      coalesce(ua.silver_badges,0) as silver_badges,
      coalesce(ua.bronze_badges,0) as bronze_badges,
      oa.q_count as user_q_count,
      oa.avg_q_score,
      oa.avg_q_views,
      oa.total_favs as user_total_favs,
      oa.closed_questions,
      qs.q_score,
      qs.q_views,
      qs.q_answercount,
      qs.upvotes,
      qs.downvotes,
      qs.total_votes,
      qs.comment_count,
      qs.edits,
      qs.closes,
      qs.reopens,
      qs.duplicate_count,
      qs.engagement_score,
      qs.views_per_comment,
      qs.net_per_answer,
      qs.interaction_span_hours,
      rank() over (order by qs.engagement_score desc nulls last) as global_rank,
      qb.top_tag,
      qb.tag_count as top_tag_count,
      au.website_norm,
      au.active_days,
      au.net_votes as user_net_votes,
      case
        when au.reputation >= 100000 then 'legend'
        when au.reputation >= 20000 then 'expert'
        when au.reputation >= 5000 then 'pro'
        when au.reputation >= 1000 then 'intermediate'
        else 'novice'
      end as rep_band,
      case
        when au.active_days >= 3650 then 'veteran'
        when au.active_days >= 1825 then 'longtime'
        when au.active_days >= 365 then 'yearling'
        else 'newcomer'
      end as tenure_band
    from q_scorecard qs
    left join active_users au on au.user_id = qs.owner_user_id
    left join user_badges ua on ua.userid = qs.owner_user_id
    left join owner_agg oa on oa.user_id = qs.owner_user_id
    left join q_best_tag qb on qb.question_id = qs.question_id
    where qs.duplicate_count >= 5
  ) c2
  left join accepted_answer aa2 on aa2.question_id = c2.question_id
)
select
  f.question_id,
  coalesce(f.title, '(no title)') as title,
  f.owner_user_id,
  coalesce(f.displayname, '(unknown)') as owner_displayname,
  f.reputation,
  f.rep_band,
  f.tenure_band,
  f.badge_total,
  f.gold_badges,
  f.silver_badges,
  f.bronze_badges,
  f.user_q_count,
  round(coalesce(f.avg_q_score,0), 2) as avg_q_score,
  round(coalesce(f.avg_q_views,0), 2) as avg_q_views,
  f.user_total_favs,
  f.closed_questions,
  f.q_score,
  f.q_views,
  f.q_answercount,
  f.upvotes,
  f.downvotes,
  f.total_votes,
  f.comment_count,
  f.edits,
  f.closes,
  f.reopens,
  f.duplicate_count,
  round(coalesce(f.engagement_score,0), 2) as engagement_score,
  round(coalesce(f.views_per_comment,0), 2) as views_per_comment,
  round(coalesce(f.net_per_answer,0), 2) as net_per_answer,
  round(coalesce(f.interaction_span_hours,0), 2) as interaction_span_hours,
  f.global_rank,
  coalesce(f.top_tag, '(untagged)') as top_tag,
  coalesce(f.top_tag_count, 0) as top_tag_count,
  f.website_norm,
  f.active_days,
  f.user_net_votes,
  coalesce(f.accepted_answer_score, 0) as accepted_answer_score,
  case
    when f.q_views is null or f.q_views = 0 then 'low-visibility'
    when f.q_views >= 100000 then 'viral'
    when f.q_views >= 10000 then 'popular'
    when f.q_views >= 1000 then 'visible'
    else 'niche'
  end as visibility_bucket
from final_union f
where
  (
    f.duplicate_count >= 3
    or (f.engagement_score is not null and f.engagement_score > 500)
    or (f.accepted_answer_score is not null and f.accepted_answer_score >= 5)
  )
  and (
    f.top_tag is null
    or f.top_tag !~ '(^|-)meta'
    or position('sql' in lower(coalesce(f.top_tag, ''))) > 0
  )
  and coalesce(nullif(trim(f.website_norm), 'n/a'), '') not like '%example.com%'
order by
  f.global_rank nulls last,
  f.engagement_score desc nulls last,
  f.q_views desc,
  f.question_id
limit 500;