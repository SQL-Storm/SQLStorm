-- {"query": "557.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2967} 
with
-- Parameterizable time window; replace dates as needed
params as (
  select
    timestamp '2015-01-01' as start_date,
    timestamp '2020-12-31' as end_date
),
-- Parse tags into array and normalize title/body snippets for string ops
questions as (
  select
    p.Id,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    coalesce(nullif(trim(p.Title), ''), '(no title)') as Title,
    string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><') as tag_arr,
    p.AnswerCount,
    p.ClosedDate,
    p.AcceptedAnswerId
  from Posts p
  join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
  join params pr on p.CreationDate between pr.start_date and pr.end_date
),
-- Answers in window; include orphaned owners and potential null parent linkage
answers as (
  select
    a.Id,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate
  from Posts a
  join PostTypes pt on pt.Id = a.PostTypeId and pt.Name = 'Answer'
  join params pr on a.CreationDate between pr.start_date and pr.end_date
),
-- Compute per-question engagement using window functions
q_metrics as (
  select
    q.Id as QuestionId,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.ClosedDate,
    q.AcceptedAnswerId,
    q.tag_arr,
    -- rolling rank by score within calendar month
    rank() over (partition by date_trunc('month', q.CreationDate) order by q.Score desc, q.ViewCount desc, q.Id) as month_rank_by_score,
    -- dense rank by views to test tie behavior
    dense_rank() over (partition by date_trunc('month', q.CreationDate) order by q.ViewCount desc) as month_dense_rank_by_views,
    -- popularity z-ish score combining log views and answers
    (coalesce(q.AnswerCount,0) * 1.0 + ln(nullif(greatest(q.ViewCount,1),0))) as popularity_score
  from questions q
),
-- Derive tag facts and join to Tags table via tag name membership
tag_facts as (
  select
    qm.QuestionId,
    unnest(qm.tag_arr) as TagName
  from q_metrics qm
),
-- Left join to Tags metadata to test null logic for unknown tags
tag_aug as (
  select
    tf.QuestionId,
    tf.TagName,
    t.Count as TagGlobalCount,
    t.IsModeratorOnly,
    t.IsRequired
  from tag_facts tf
  left join Tags t
    on lower(t.TagName) = lower(tf.TagName)
),
-- Aggregate tag stats per question
tag_agg as (
  select
    QuestionId,
    count(*) as tag_count,
    sum(coalesce(TagGlobalCount,0)) as sum_tag_popularity,
    bool_or(coalesce(IsModeratorOnly, 0) = 1) as has_mod_only,
    bool_or(coalesce(IsRequired, 0) = 1) as has_required
  from tag_aug
  group by QuestionId
),
-- Votes breakdown on questions and answers
vote_agg as (
  select
    v.PostId,
    sum(case when vt.Name = 'UpMod' then 1 else 0 end) as upvotes,
    sum(case when vt.Name = 'DownMod' then 1 else 0 end) as downvotes,
    sum(case when vt.Name = 'Favorite' then 1 else 0 end) as favorites,
    sum(case when vt.Name = 'Spam' then 1 else 0 end) as spam_votes
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
-- Comments toxicity/profanity proxy and length metrics
comment_agg as (
  select
    c.PostId,
    count(*) as comment_count,
    sum(case when c.Score < 0 then 1 else 0 end) as neg_comment_count,
    avg(nullif(length(c.Text),0)) as avg_comment_len,
    max(length(c.Text)) as max_comment_len,
    sum(case when c.Text ~* '(?<![a-z])(?:(?:wtf)|(?:damn)|(?:shit)|(?:crap))(?![a-z])' then 1 else 0 end) as profanity_hits
  from Comments c
  group by c.PostId
),
-- Link-based relations: duplicates and general links
link_agg as (
  select
    pl.PostId,
    sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as dup_out_count,
    sum(case when lt.Name = 'Linked' then 1 else 0 end) as link_out_count
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId
),
-- Close reasons pulled from PostHistory with JSON/text content
close_events as (
  select
    ph.PostId,
    min(ph.CreationDate) as first_close_ts,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as last_reopen_ts,
    -- parse integer close reason where applicable
    max(
      case when ph.PostHistoryTypeId = 10
           then nullif(regexp_replace(coalesce(ph.Comment,''), '[^0-9]', '', 'g'), '')
      end
    )::int as close_reason_id
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11)
  group by ph.PostId
),
-- Badge influence: compute a user "prestige" at time of question using correlated subquery
user_prestige as (
  select
    u.Id as UserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    -- overall badge weighted score
    coalesce((
      select sum(case b.Class when 1 then 9 when 2 then 3 else 1 end)
      from Badges b
      where b.UserId = u.Id
    ),0) as badge_weight_all
  from Users u
),
-- Accepted answer responsiveness: time to accepted, join against answer/accepted
accept_metrics as (
  select
    q.Id as QuestionId,
    case when q.AcceptedAnswerId is not null then
      (select extract(epoch from (a.CreationDate - q.CreationDate))/3600.0
       from Posts a
       where a.Id = q.AcceptedAnswerId)
    end as hours_to_accept
  from questions q
),
-- Answerers diversity and top answer score per question
answer_agg as (
  select
    a.QuestionId,
    count(*) as answer_count_window,
    count(distinct a.OwnerUserId) as distinct_answerers,
    max(a.Score) as max_answer_score,
    avg(a.Score) as avg_answer_score
  from answers a
  group by a.QuestionId
),
-- Bring everything together at question grain
question_full as (
  select
    qm.QuestionId,
    qm.OwnerUserId,
    qm.CreationDate,
    qm.Score,
    qm.ViewCount,
    qm.AnswerCount,
    qm.ClosedDate,
    qm.AcceptedAnswerId,
    qm.month_rank_by_score,
    qm.month_dense_rank_by_views,
    qm.popularity_score,
    ta.tag_count,
    ta.sum_tag_popularity,
    ta.has_mod_only,
    ta.has_required,
    vaq.upvotes as q_upvotes,
    vaq.downvotes as q_downvotes,
    vaq.favorites as q_favorites,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(ca.neg_comment_count,0) as neg_comment_count,
    coalesce(ca.avg_comment_len,0) as avg_comment_len,
    coalesce(ca.max_comment_len,0) as max_comment_len,
    coalesce(ca.profanity_hits,0) as profanity_hits,
    coalesce(la.dup_out_count,0) as dup_out_count,
    coalesce(la.link_out_count,0) as link_out_count,
    ce.first_close_ts,
    ce.last_reopen_ts,
    ce.close_reason_id,
    am.answer_count_window,
    am.distinct_answerers,
    am.max_answer_score,
    am.avg_answer_score,
    acm.hours_to_accept
  from q_metrics qm
  left join tag_agg ta on ta.QuestionId = qm.QuestionId
  left join vote_agg vaq on vaq.PostId = qm.QuestionId
  left join comment_agg ca on ca.PostId = qm.QuestionId
  left join link_agg la on la.PostId = qm.QuestionId
  left join close_events ce on ce.PostId = qm.QuestionId
  left join answer_agg am on am.QuestionId = qm.QuestionId
  left join accept_metrics acm on acm.QuestionId = qm.QuestionId
),
-- Enrich with user features and reputation buckets
question_user as (
  select
    qf.*,
    u.DisplayName,
    u.Location,
    up.Reputation,
    up.UpVotes as user_upvotes,
    up.DownVotes as user_downvotes,
    up.Views as user_views,
    up.badge_weight_all,
    case
      when up.Reputation >= 100000 then 'Legend'
      when up.Reputation >= 25000 then 'High'
      when up.Reputation >= 5000 then 'Mid'
      when up.Reputation >= 500 then 'Low'
      else 'New'
    end as rep_bucket
  from question_full qf
  left join Users u on u.Id = qf.OwnerUserId
  left join user_prestige up on up.UserId = qf.OwnerUserId
),
-- Compute composite quality score with null-safe arithmetic and conditional boosts/penalties
scored as (
  select
    qu.*,
    (
      coalesce(qu.Score,0) * 2.0
      + ln(nullif(greatest(qu.ViewCount,1),0)) * 1.5
      + coalesce(qu.q_upvotes,0) * 1.25
      - coalesce(qu.q_downvotes,0) * 2.0
      + coalesce(qu.q_favorites,0) * 3.0
      + coalesce(qu.answer_count_window, coalesce(qu.AnswerCount,0)) * 1.2
      + case when qu.hours_to_accept is not null then greatest(0.0, 48.0 - qu.hours_to_accept) * 0.1 else 0 end
      + case when qu.has_mod_only then -5 else 0 end
      + case when qu.has_required then 1 else 0 end
      - coalesce(qu.profanity_hits,0) * 4
      - case when qu.close_reason_id is not null then 10 else 0 end
      + case when qu.rep_bucket in ('Legend','High') then 2 else 0 end
    ) as quality_score
  from question_user qu
),
-- Rank and filter with complex predicates to widen planning surface
ranked as (
  select
    s.*,
    row_number() over (
      partition by date_trunc('month', s.CreationDate)
      order by s.quality_score desc, s.ViewCount desc, s.Score desc, s.QuestionId
    ) as rn_month,
    percentile_cont(0.9) within group (order by s.quality_score) over () as p90_quality_global
  from scored s
  where
    -- complicated predicate mixing null logic and string ops
    (
      s.Title ilike any (array['%performance%','%optimiz%','%index%','%join%'])
      or exists (
        select 1
        from unnest(coalesce(s.tag_arr, array[]::varchar[])) t(tag)
        where lower(t.tag) in ('sql', 'postgresql', 'performance', 'tuning')
      )
    )
    and coalesce(s.ViewCount,0) + coalesce(s.q_upvotes,0) - coalesce(s.q_downvotes,0) >= 0
    and (s.last_reopen_ts is null or s.last_reopen_ts >= s.first_close_ts)
)
select
  r.QuestionId,
  r.Title,
  r.CreationDate,
  r.OwnerUserId,
  coalesce(r.DisplayName, '(anonymous)') as OwnerDisplayName,
  r.rep_bucket,
  r.Score,
  r.ViewCount,
  r.q_upvotes,
  r.q_downvotes,
  r.q_favorites,
  r.AnswerCount,
  r.answer_count_window,
  r.distinct_answerers,
  r.month_rank_by_score,
  r.month_dense_rank_by_views,
  r.hours_to_accept,
  r.tag_count,
  r.sum_tag_popularity,
  r.dup_out_count,
  r.link_out_count,
  r.comment_count,
  r.neg_comment_count,
  round(coalesce(r.avg_comment_len,0)::numeric,2) as avg_comment_len,
  r.max_comment_len,
  r.close_reason_id,
  r.first_close_ts,
  r.last_reopen_ts,
  round(r.quality_score::numeric,3) as quality_score,
  r.p90_quality_global,
  case when r.quality_score >= r.p90_quality_global then 'Top10%' else 'Normal' end as quality_band
from ranked r
where r.rn_month <= 50
order by r.quality_score desc, r.ViewCount desc, r.Score desc, r.QuestionId
limit 500;