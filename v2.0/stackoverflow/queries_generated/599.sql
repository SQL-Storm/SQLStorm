-- {"query": "599.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3457} 
with
-- Parameterizable date boundaries
bounds as (
  select
    coalesce(min(u.CreationDate), timestamp '1900-01-01') as min_user_date,
    coalesce(max(u.CreationDate), now()) as max_user_date,
    coalesce(min(p.CreationDate), timestamp '1900-01-01') as min_post_date,
    coalesce(max(p.CreationDate), now()) as max_post_date
  from Users u
  cross join Posts p
),
-- Active users with activity windows and basic aggregates
active_users as (
  select
    u.Id as user_id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    date_trunc('month', u.CreationDate) as cohort_month,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    coalesce(nullif(trim(u.WebsiteUrl), ''), 'n/a') as website_norm,
    (u.UpVotes - u.DownVotes) as vote_delta,
    count(distinct p.Id) filter (where p.OwnerUserId = u.Id) as authored_posts,
    count(distinct c.Id) filter (where c.UserId = u.Id) as authored_comments,
    count(distinct b.Id) as badge_count,
    min(p.CreationDate) filter (where p.OwnerUserId = u.Id) as first_post_date,
    max(p.LastActivityDate) filter (where p.OwnerUserId = u.Id) as last_post_activity
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate, u.UpVotes, u.DownVotes, u.Views, u.WebsiteUrl
),
-- Questions with tagging, closure, acceptance, and engagement metrics
questions as (
  select
    q.Id as question_id,
    q.OwnerUserId as asker_id,
    q.CreationDate as q_created,
    q.ClosedDate,
    q.AcceptedAnswerId,
    q.Score as q_score,
    q.ViewCount,
    q.AnswerCount,
    q.Title,
    q.Tags,
    array_length(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><'), 1) as tag_count,
    exists (
      select 1
      from PostHistory ph
      where ph.PostId = q.Id
        and ph.PostHistoryTypeId in (10,35) -- closed or migrated
      limit 1
    ) as had_moderation,
    -- string/NULL logic: normalize tags text
    case
      when q.Tags is null then 'untagged'
      when length(trim(q.Tags)) = 0 then 'untagged'
      else lower(q.Tags)
    end as tags_norm
  from Posts q
  where q.PostTypeId = 1
),
-- Answers with responder info and scoring
answers as (
  select
    a.Id as answer_id,
    a.ParentId as question_id,
    a.OwnerUserId as answerer_id,
    a.CreationDate as a_created,
    a.Score as a_score,
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn_by_score,
    count(*) over (partition by a.ParentId) as total_answers_for_question
  from Posts a
  where a.PostTypeId = 2
),
-- Votes rollups for posts
post_votes as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as bounty_amount,
    min(v.CreationDate) as first_vote_at,
    max(v.CreationDate) as last_vote_at
  from Votes v
  group by v.PostId
),
-- Extract duplicate link graph edges
duplicate_links as (
  select
    pl.PostId as dup_post_id,
    pl.RelatedPostId as canonical_post_id,
    pl.CreationDate as link_date
  from PostLinks pl
  where pl.LinkTypeId = 3
),
-- Compute time-to-first-answer and acceptance flags
question_answer_metrics as (
  select
    q.question_id,
    q.asker_id,
    q.q_created,
    q.ClosedDate,
    q.AcceptedAnswerId,
    q.q_score,
    q.ViewCount,
    q.AnswerCount,
    q.Title,
    q.Tags,
    q.tag_count,
    q.had_moderation,
    q.tags_norm,
    min(a.a_created) as first_answer_at,
    sum(case when a.answer_id = q.AcceptedAnswerId then 1 else 0 end) as has_accepted_answer,
    sum(case when a.rn_by_score = 1 then 1 else 0 end) as has_top_answer,
    avg(a.a_score::numeric) as avg_answer_score,
    max(a.total_answers_for_question) as total_answers
  from questions q
  left join answers a on a.question_id = q.question_id
  group by q.question_id, q.asker_id, q.q_created, q.ClosedDate, q.AcceptedAnswerId, q.q_score, q.ViewCount, q.AnswerCount, q.Title, q.Tags, q.tag_count, q.had_moderation, q.tags_norm
),
-- Pull in votes for question and accepted answer (if any)
qa_with_votes as (
  select
    qam.*,
    pv_q.upvotes as q_upvotes,
    pv_q.downvotes as q_downvotes,
    pv_q.favorites as q_favorites,
    pv_q.bounty_amount as q_bounty,
    pv_a.upvotes as acc_upvotes,
    pv_a.downvotes as acc_downvotes
  from question_answer_metrics qam
  left join post_votes pv_q on pv_q.PostId = qam.question_id
  left join post_votes pv_a on pv_a.PostId = qam.AcceptedAnswerId
),
-- Compute per-user rolling activity using window functions
user_activity as (
  select
    au.user_id,
    au.DisplayName,
    au.Reputation,
    au.Location,
    au.cohort_month,
    au.vote_delta,
    au.authored_posts,
    au.authored_comments,
    au.badge_count,
    au.first_post_date,
    au.last_post_activity,
    sum(au.authored_posts) over (partition by au.user_id order by au.cohort_month rows between unbounded preceding and current row) as cum_posts,
    sum(au.authored_comments) over (partition by au.user_id order by au.cohort_month rows between unbounded preceding and current row) as cum_comments
  from active_users au
),
-- Correlated subquery: find user's most used tag on questions they asked
user_top_tag as (
  select
    q.asker_id as user_id,
    tname,
    cnt,
    row_number() over (partition by q.asker_id order by cnt desc, tname) as rn
  from (
    select
      q.asker_id,
      unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tname,
      count(*) as cnt
    from questions q
    where q.Tags is not null
    group by q.asker_id, unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><'))
  ) s
),
-- Tag popularity slice via set operators
popular_tags as (
  select t.TagName, t.Count
  from Tags t
  where t.Count > (select avg(Count) from Tags)
  intersect
  select t.TagName, t.Count
  from Tags t
  where t.IsModeratorOnly is distinct from 1
),
-- Identify duplicates and canonical mapping
dup_map as (
  select
    d.dup_post_id,
    d.canonical_post_id,
    d.link_date,
    case
      when q.AcceptedAnswerId is not null then 'dup_with_accept'
      else 'dup_no_accept'
    end as dup_class
  from duplicate_links d
  left join questions q on q.question_id = d.dup_post_id
),
-- Build a mixed-quality score using various signals
quality_scores as (
  select
    qv.question_id,
    qv.asker_id,
    -- Weighted composite score
    (
      coalesce(qv.q_upvotes,0) * 3
      - coalesce(qv.q_downvotes,0) * 5
      + coalesce(qv.q_favorites,0) * 2
      + coalesce(qv.q_bounty,0) / 50.0
      + coalesce(qv.acc_upvotes,0) * 1.5
      + coalesce(qv.avg_answer_score,0) * 1.0
      + case when qv.has_accepted_answer > 0 then 5 else 0 end
      + case when qv.had_moderation then -4 else 0 end
      + least(coalesce(qv.ViewCount,0) / 1000.0, 10)
    )::numeric(18,4) as quality_score,
    -- Time to first answer in hours (NULL-safe)
    extract(epoch from (qv.first_answer_at - qv.q_created)) / 3600.0 as t_first_answer_hours,
    qv.q_score,
    qv.ViewCount,
    qv.tag_count
  from qa_with_votes qv
),
-- Rank questions per tag by composite quality
ranked_by_tag as (
  select
    qv.question_id,
    tname,
    qs.quality_score,
    row_number() over (partition by tname order by qs.quality_score desc nulls last, qv.question_id) as rn_tag,
    dense_rank() over (order by qs.quality_score desc nulls last) as global_rank
  from questions qv
  join lateral (
    select unnest(string_to_array(substring(qv.Tags, 2, greatest(length(qv.Tags)-2,0)), '><')) as tname
  ) t on true
  join quality_scores qs on qs.question_id = qv.question_id
),
-- Per-user summary, joining top tag if present
user_summary as (
  select
    ua.user_id,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.cohort_month,
    ua.vote_delta,
    ua.authored_posts,
    ua.authored_comments,
    ua.badge_count,
    ua.cum_posts,
    ua.cum_comments,
    coalesce((select ut.tname from user_top_tag ut where ut.user_id = ua.user_id and ut.rn = 1), 'none') as top_tag
  from user_activity ua
),
-- Windowed percentile ranks for performance spread
distribution as (
  select
    qs.question_id,
    qs.quality_score,
    ntile(100) over (order by qs.quality_score nulls last) as pctile,
    avg(qs.quality_score) over () as avg_quality,
    stddev_pop(qs.quality_score) over () as std_quality
  from quality_scores qs
),
-- Identify edge cases: untagged or zero-answer questions as outliers
outliers as (
  select
    qv.question_id,
    case
      when qv.Tags is null or trim(qv.Tags) = '' then 'untagged'
      when coalesce(qv.AnswerCount,0) = 0 then 'no_answers'
      when qv.ClosedDate is not null then 'closed'
      else 'normal'
    end as outlier_class
  from questions qv
)
select
  -- Final, wide result for benchmarking joins, windows, subqueries, expressions, and NULL logic
  q.question_id,
  q.Title,
  q.tags_norm as tags_raw_lower,
  coalesce(rb.tname, 'none') as sample_tag,
  pv.upvotes as q_upvotes,
  pv.downvotes as q_downvotes,
  pv.favorites as q_favorites,
  pv.bounty_amount as q_bounty,
  coalesce(qs.quality_score, 0)::numeric(18,4) as quality_score,
  coalesce(qs.t_first_answer_hours, -1) as hours_to_first_answer,
  d.pctile as quality_percentile,
  d.avg_quality,
  d.std_quality,
  os.outlier_class,
  coalesce(dm.dup_class, 'not_duplicate') as duplicate_class,
  coalesce(ut.top_tag, 'none') as asker_top_tag,
  u.DisplayName as asker_name,
  u.Reputation as asker_rep,
  u.vote_delta as asker_vote_delta,
  u.badge_count as asker_badges,
  u.cum_posts as asker_cum_posts,
  u.cum_comments as asker_cum_comments,
  -- Complex predicate output
  case
    when q.tag_count >= 5 and pv.upvotes >= 10 and pv.downvotes = 0 then 'highly_tagged_and_loved'
    when q.tag_count between 1 and 2 and coalesce(pv.upvotes,0) < coalesce(pv.downvotes,0) then 'lightly_tagged_and_divisive'
    when pv.upvotes is null and pv.downvotes is null then 'no_votes'
    else 'other'
  end as engagement_class,
  -- String manipulation and NULL handling
  left(regexp_replace(coalesce(q.Title, ''), '\s+', ' ', 'g'), 120) as truncated_clean_title,
  -- Derived measures
  coalesce(q.ViewCount,0) / nullif(greatest(1, q.AnswerCount), 0)::numeric as views_per_answer,
  -- Correlated subquery: latest comment excerpt on the question
  (
    select left(cc.Text, 80)
    from Comments cc
    where cc.PostId = q.question_id
    order by cc.Score desc nulls last, cc.CreationDate desc
    limit 1
  ) as top_comment_excerpt
from questions q
left join post_votes pv on pv.PostId = q.question_id
left join quality_scores qs on qs.question_id = q.question_id
left join distribution d on d.question_id = q.question_id
left join outliers os on os.question_id = q.question_id
left join dup_map dm on dm.dup_post_id = q.question_id
left join user_summary u on u.user_id = q.asker_id
left join user_summary ut on ut.user_id = q.asker_id
left join lateral (
  select tname
  from ranked_by_tag rbt
  where rbt.question_id = q.question_id
  order by rbt.rn_tag
  limit 1
) rb on true
-- A mixture of complex predicates to stress planners
where
  (
    (qs.quality_score is null and q.ViewCount is not null)
    or (qs.quality_score > coalesce(d.avg_quality, 0) + coalesce(d.std_quality, 0))
    or (os.outlier_class in ('untagged','no_answers') and coalesce(pv.upvotes,0) <= 1)
  )
  and (
    -- substring search across normalized tags
    q.tags_norm like any (array['%<sql>%','%<postgresql>%','%<performance>%'])
    or q.tag_count is null
  )
  and (
    q.q_score is distinct from 0
    or q.AnswerCount is distinct from 0
  )
order by
  coalesce(qs.quality_score, -9999) desc nulls last,
  q.ViewCount desc nulls last,
  q.question_id
limit 500;