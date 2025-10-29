-- {"query": "310.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3462} 
with
-- Normalize tags into rows for questions
question_tags as (
  select
    p.id as question_id,
    lower(trim(t)) as tag
  from posts p
  cross join lateral unnest(
    case
      when p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
        then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
      else array[]::varchar[]
    end
  ) as t
  where p.posttypeid = 1
),
-- Compute user engagement metrics with window functions
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(u.location, 'Unknown') as location,
    count(distinct p.id) filter (where p.posttypeid = 1) as questions_posted,
    count(distinct p.id) filter (where p.posttypeid = 2) as answers_posted,
    sum(greatest(p.score, 0)) as total_positive_score,
    sum(least(p.score, 0)) as total_negative_score,
    count(distinct c.id) as comments_made,
    coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end), 0) as net_votes_cast,
    row_number() over (partition by (case when u.location is null then 'Unknown' else u.location end) order by u.reputation desc, u.id) as rn_by_location,
    percentile_disc(0.9) within group (order by coalesce(p.score, 0)) over (partition by u.id) as p90_post_score
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join votes v on v.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location
),
-- Question level aggregates: activity, closure, duplication, acceptance
question_stats as (
  select
    q.id as question_id,
    q.owneruserid,
    q.creationdate,
    q.score,
    q.viewcount,
    q.answercount,
    q.closeddate,
    q.acceptedanswerid,
    q.title,
    count(distinct a.id) filter (where a.posttypeid = 2) as answers_total,
    max(case when a.id = q.acceptedanswerid then 1 else 0 end) as has_accepted_answer,
    count(distinct v.id) filter (where v.votetypeid = 2) as upvotes,
    count(distinct v.id) filter (where v.votetypeid = 3) as downvotes,
    count(distinct c.id) as comment_count,
    bool_or(pl.linktypeid = 3) as is_marked_duplicate,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_event,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_event
  from posts q
  left join posts a on a.parentid = q.id
  left join votes v on v.postid = q.id
  left join comments c on c.postid = q.id
  left join postlinks pl on pl.postid = q.id and pl.linktypeid in (1,3)
  left join posthistory ph on ph.postid = q.id and ph.posthistorytypeid in (10,11)
  where q.posttypeid = 1
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount, q.closeddate, q.acceptedanswerid, q.title
),
-- Badge summary per user
badge_summary as (
  select
    b.userid,
    count(*) as badges_total,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
-- Tag popularity and entropy around each question's tag set
question_tag_stats as (
  select
    qt.question_id,
    count(*) as tag_count,
    sum(t.count) as tag_usage_total,
    exp(-sum((t.count::numeric / nullif(sum(t.count) over (partition by qt.question_id),0)) * ln(nullif(t.count::numeric / nullif(sum(t.count) over (partition by qt.question_id),0),0)))) as tag_entropy
  from question_tags qt
  left join tags t on t.tagname = qt.tag
  group by qt.question_id
),
-- Recent activity windows
recent_activity as (
  select
    p.id as post_id,
    count(*) filter (where v.votetypeid = 2 and v.creationdate >= p.creationdate) as upvotes_since_post,
    count(*) filter (where v.votetypeid = 3 and v.creationdate >= p.creationdate) as downvotes_since_post,
    count(*) filter (where c.creationdate >= p.creationdate) as comments_since_post,
    max(v.creationdate) as last_vote_at,
    max(c.creationdate) as last_comment_at
  from posts p
  left join votes v on v.postid = p.id
  left join comments c on c.postid = p.id
  group by p.id
),
-- Correlated subquery via lateral: first duplicate target title if any
dup_target as (
  select
    q.id as question_id,
    dp.relatedpostid as target_id,
    p2.title as target_title
  from posts q
  left join lateral (
    select pl.relatedpostid
    from postlinks pl
    where pl.postid = q.id and pl.linktypeid = 3
    order by pl.creationdate asc, pl.id asc
    limit 1
  ) dp on true
  left join posts p2 on p2.id = dp.relatedpostid
  where q.posttypeid = 1
),
-- Derive close reasons with JSON in PostHistory.Text
close_reasons as (
  select
    ph.postid as question_id,
    min(ph.creationdate) as first_close_at,
    substring(ph.comment from '([0-9]+)')::int as close_reason_id,
    max(ph.text) as close_payload
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid, substring(ph.comment from '([0-9]+)')
),
-- Rank questions by a composite score
ranked_questions as (
  select
    qs.question_id,
    qs.owneruserid,
    qs.creationdate,
    qs.title,
    coalesce(qs.viewcount,0) as viewcount,
    coalesce(qs.score,0) as score,
    coalesce(qs.answers_total,0) as answers_total,
    coalesce(qs.upvotes,0) as upvotes,
    coalesce(qs.downvotes,0) as downvotes,
    coalesce(qs.comment_count,0) as comment_count,
    coalesce(qts.tag_count,0) as tag_count,
    coalesce(qts.tag_usage_total,0) as tag_usage_total,
    coalesce(qts.tag_entropy,1) as tag_entropy,
    case when qs.has_accepted_answer = 1 then 1 else 0 end as has_accepted_answer,
    case when qs.is_marked_duplicate then 1 else 0 end as is_marked_duplicate,
    coalesce(extract(epoch from (now() - qs.creationdate)) / 86400.0, 0) as age_days,
    -- composite metric with non-linear pieces
    (
      (ln(1 + greatest(qs.viewcount,0)) * 0.4) +
      (coalesce(qs.score,0) * 0.6) +
      (case when qs.has_accepted_answer = 1 then 5 else 0 end) -
      (case when qs.is_marked_duplicate then 3 else 0 end) +
      (least(coalesce(qts.tag_entropy,1), 5) * 0.7) +
      (ln(1 + coalesce(qs.comment_count,0)) * 0.2)
    ) as composite_score
  from question_stats qs
  left join question_tag_stats qts on qts.question_id = qs.question_id
),
-- Window ranks per tag and overall
per_tag_ranks as (
  select
    rq.*,
    qt.tag,
    row_number() over (partition by qt.tag order by rq.composite_score desc, rq.question_id desc) as rn_tag,
    dense_rank() over (order by rq.composite_score desc, rq.question_id desc) as dr_overall
  from ranked_questions rq
  left join question_tags qt on qt.question_id = rq.question_id
),
-- Aggregate back per-question choosing best tag rank
question_best_tag as (
  select
    ptr.question_id,
    min(ptr.rn_tag) as best_tag_rank,
    array_agg(distinct ptr.tag order by ptr.tag) filter (where ptr.tag is not null) as tags
  from per_tag_ranks ptr
  group by ptr.question_id
),
-- User-level rollup combining everything
user_rollup as (
  select
    ua.user_id,
    ua.displayname,
    ua.reputation,
    ua.location,
    ua.questions_posted,
    ua.answers_posted,
    ua.total_positive_score + ua.total_negative_score as posts_net_score,
    ua.comments_made,
    ua.net_votes_cast,
    ua.rn_by_location,
    ua.p90_post_score,
    coalesce(bs.badges_total,0) as badges_total,
    coalesce(bs.gold_badges,0) as gold_badges,
    coalesce(bs.silver_badges,0) as silver_badges,
    coalesce(bs.bronze_badges,0) as bronze_badges,
    coalesce(bs.tag_badges,0) as tag_badges
  from user_activity ua
  left join badge_summary bs on bs.userid = ua.user_id
),
-- Bring everything per question
final_questions as (
  select
    rq.question_id,
    rq.owneruserid as user_id,
    rq.title,
    rq.creationdate,
    rq.viewcount,
    rq.score,
    rq.answers_total,
    rq.upvotes,
    rq.downvotes,
    rq.comment_count,
    rq.tag_count,
    rq.tag_usage_total,
    rq.tag_entropy,
    rq.has_accepted_answer,
    rq.is_marked_duplicate,
    rq.age_days,
    rq.composite_score,
    qb.best_tag_rank,
    qb.tags,
    ra.upvotes_since_post,
    ra.downvotes_since_post,
    ra.comments_since_post,
    ra.last_vote_at,
    ra.last_comment_at,
    cr.first_close_at,
    cr.close_reason_id,
    cr.close_payload,
    dt.target_id as dup_target_id,
    dt.target_title as dup_target_title
  from ranked_questions rq
  left join question_best_tag qb on qb.question_id = rq.question_id
  left join recent_activity ra on ra.post_id = rq.question_id
  left join close_reasons cr on cr.question_id = rq.question_id
  left join dup_target dt on dt.question_id = rq.question_id
),
-- Compute per-user statistics over their questions
user_question_stats as (
  select
    fq.user_id,
    count(*) as q_count,
    avg(fq.composite_score) as avg_q_score,
    max(fq.composite_score) as max_q_score,
    sum(case when fq.has_accepted_answer = 1 then 1 else 0 end) as q_with_accept,
    sum(case when fq.is_marked_duplicate = 1 then 1 else 0 end) as q_duplicates,
    percentile_cont(0.5) within group (order by fq.viewcount) as median_views,
    sum(coalesce(fq.upvotes,0) - coalesce(fq.downvotes,0)) as net_votes_on_q
  from final_questions fq
  group by fq.user_id
),
-- Synthesize an overall user score combining rollups and behavior
user_overall as (
  select
    ur.*,
    uqs.q_count,
    uqs.avg_q_score,
    uqs.max_q_score,
    uqs.q_with_accept,
    uqs.q_duplicates,
    uqs.median_views,
    uqs.net_votes_on_q,
    (
      ln(1 + coalesce(ur.reputation,0)) * 0.5
      + coalesce(ur.badges_total,0) * 0.2
      + coalesce(uqs.avg_q_score,0) * 1.2
      + greatest(coalesce(ur.answers_posted,0) - coalesce(uqs.q_duplicates,0), 0) * 0.1
      + case when coalesce(ur.location,'') ilike '%remote%' then 0.1 else 0 end
      - case when coalesce(ur.downvotes,0) > coalesce(ur.upvotes,0) then 1 else 0 end
    ) as overall_user_score
  from user_rollup ur
  left join user_question_stats uqs on uqs.user_id = ur.user_id
)
select
  fq.question_id,
  fq.title,
  fq.user_id,
  coalesce(u.displayname, '(unknown)') as user_displayname,
  uo.overall_user_score,
  uo.reputation,
  uo.badges_total,
  uo.gold_badges,
  uo.silver_badges,
  uo.bronze_badges,
  uo.tag_badges,
  uo.q_count,
  uo.avg_q_score,
  uo.max_q_score,
  uo.q_with_accept,
  uo.q_duplicates,
  uo.median_views,
  uo.net_votes_on_q,
  fq.viewcount,
  fq.score,
  fq.answers_total,
  fq.upvotes,
  fq.downvotes,
  fq.comment_count,
  fq.tag_count,
  fq.tag_usage_total,
  fq.tag_entropy,
  fq.has_accepted_answer,
  fq.is_marked_duplicate,
  fq.age_days,
  fq.composite_score,
  fq.best_tag_rank,
  fq.tags,
  fq.upvotes_since_post,
  fq.downvotes_since_post,
  fq.comments_since_post,
  fq.last_vote_at,
  fq.last_comment_at,
  fq.first_close_at,
  crt.name as close_reason_name,
  fq.close_payload,
  fq.dup_target_id,
  fq.dup_target_title
from final_questions fq
left join users u on u.id = fq.user_id
left join user_overall uo on uo.user_id = fq.user_id
left join closereasontypes crt on crt.id = fq.close_reason_id
where
  -- complicated predicate mixing null logic, string and numeric conditions
  (
    fq.is_marked_duplicate = 0
    or (fq.is_marked_duplicate = 1 and fq.has_accepted_answer = 1 and coalesce(fq.viewcount,0) > 100)
  )
  and coalesce(uo.overall_user_score, 0) >= (
    select avg(coalesce(uo2.overall_user_score,0)) + stddev_pop(coalesce(uo2.overall_user_score,0))
    from user_overall uo2
  )
  and (
    fq.tag_entropy is null
    or fq.tag_entropy between 0.5 and 5.0
    or fq.tag_count = 0
  )
  and (
    fq.first_close_at is null
    or fq.close_reason_id not in (select id from closereasontypes where name ilike any (array['%opinion%','%off%topic%']))
  )
order by
  fq.composite_score desc nulls last,
  fq.viewcount desc nulls last,
  fq.question_id desc
limit 250;