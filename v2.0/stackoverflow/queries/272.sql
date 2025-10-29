-- {"query": "272.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2797}
with
q_posts as (
  select p.Id as QuestionId,
         p.Title,
         p.OwnerUserId,
         p.Score as QScore,
         p.ViewCount,
         p.CreationDate as QCreated,
         p.AcceptedAnswerId,
         p.Tags,
         coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
),
a_posts as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswerUserId,
         a.Score as AScore,
         a.CreationDate as ACreated
  from Posts a
  where a.PostTypeId = 2
),
answers_ranked as (
  select ap.QuestionId,
         ap.AnswerId,
         ap.AnswerUserId,
         ap.AScore,
         ap.ACreated,
         row_number() over (partition by ap.QuestionId order by ap.AScore desc nulls last, ap.ACreated asc nulls last, ap.AnswerId asc) as rn_top_by_score,
         row_number() over (partition by ap.QuestionId order by ap.ACreated asc nulls last, ap.AnswerId asc) as rn_earliest,
         max(case when ap.AnswerId = qp.AcceptedAnswerId then 1 else 0 end) over (partition by ap.QuestionId) as has_accepted
  from a_posts ap
  join q_posts qp on qp.QuestionId = ap.QuestionId
),
agg_answers as (
  select
    ar.QuestionId,
    count(*) as total_answers,
    sum(case when ar.AScore > 0 then 1 else 0 end) as pos_answers,
    sum(case when ar.AScore < 0 then 1 else 0 end) as neg_answers,
    avg(cast(ar.AScore as numeric)) as avg_answer_score,
    percentile_cont(0.5) within group (order by ar.AScore) as median_answer_score,
    max(ar.AScore) as max_answer_score,
    min(ar.AScore) as min_answer_score,
    sum(case when ar.rn_top_by_score = 1 then 1 else 0 end) as has_top_answer,
    sum(case when ar.rn_earliest = 1 then 1 else 0 end) as has_earliest_answer
  from answers_ranked ar
  group by ar.QuestionId
),
votes_agg as (
  select v.PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
         sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as bounty_started,
         sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as bounty_awarded,
         min(v.CreationDate) as first_vote_at,
         max(v.CreationDate) as last_vote_at
  from Votes v
  group by v.PostId
),
comments_agg as (
  select c.PostId,
         count(*) as comment_count,
         avg(cast(c.Score as numeric)) as avg_comment_score,
         max(length(c.Text)) as max_comment_len,
         min(c.CreationDate) as first_comment_at,
         max(c.CreationDate) as last_comment_at
  from Comments c
  group by c.PostId
),
question_edits as (
  select ph.PostId as QuestionId,
         count(case when ph.PostHistoryTypeId in (4,5,6) then 1 end) as edit_count,
         min(case when ph.PostHistoryTypeId in (4,5,6) then ph.CreationDate end) as first_edit_at,
         max(case when ph.PostHistoryTypeId in (4,5,6) then ph.CreationDate end) as last_edit_at,
         count(case when ph.PostHistoryTypeId = 10 then 1 end) as close_events,
         max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as integer) end) as last_close_reason_id
  from PostHistory ph
  join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
  group by ph.PostId
),
dup_links as (
  select pl.PostId as QuestionId,
         count(case when pl.LinkTypeId = 3 then 1 end) as dup_links_out,
         count(case when pl.LinkTypeId = 3 and pl.RelatedPostId is not null then 1 end) as dup_targets
  from PostLinks pl
  group by pl.PostId
),
tag_expansion as (
  select
    qp.QuestionId,
    unnest(string_to_array(substring(qp.Tags from 2 for length(qp.Tags)-2), '><')) as tagname
  from q_posts qp
  where qp.Tags is not null
),
tag_stats as (
  select te.QuestionId,
         array_agg(te.tagname order by te.tagname) as tags_sorted,
         count(*) as tag_count,
         sum(case when lower(te.tagname) like '%sql%' then 1 else 0 end) as sqlish
  from tag_expansion te
  group by te.QuestionId
),
owner_stats as (
  select u.Id as UserId,
         u.Reputation,
         u.CreationDate as UserCreated,
         u.DisplayName,
         u.UpVotes as UserUpVotes,
         u.DownVotes as UserDownVotes,
         coalesce(u.Location,'') as Location,
         count(case when b.Class = 1 then 1 end) as gold_badges,
         count(case when b.Class = 2 then 1 end) as silver_badges,
         count(case when b.Class = 3 then 1 end) as bronze_badges,
         max(b.Date) as last_badge_at
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.UpVotes, u.DownVotes, u.Location
),
question_activity as (
  select
    qp.QuestionId,
    qp.QCreated,
    coalesce(qp.ViewCount,0) as views,
    qp.QScore,
    qp.AnswerCount,
    qp.AcceptedAnswerId,
    greatest(coalesce(qp.QCreated, timestamp 'epoch'),
             coalesce(qe.last_edit_at, timestamp 'epoch'),
             coalesce(ca.last_comment_at, timestamp 'epoch'),
             coalesce(va.last_vote_at, timestamp 'epoch')) as last_touch
  from q_posts qp
  left join question_edits qe on qe.QuestionId = qp.QuestionId
  left join comments_agg ca on ca.PostId = qp.QuestionId
  left join votes_agg va on va.PostId = qp.QuestionId
),
question_quality as (
  select
    qa.QuestionId,
    case
      when qa.QScore >= 5 and coalesce(ag.total_answers,0) >= 2 then 'high'
      when qa.QScore <= 0 and coalesce(ag.total_answers,0) = 0 then 'low'
      else 'medium'
    end as quality_bucket,
    coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
    coalesce(cast(ag.avg_answer_score as numeric), 0) as avg_answer_score,
    case when qa.AcceptedAnswerId is not null then 1 else 0 end as has_accepted_answer,
    coalesce(ta.sqlish,0) as sql_tag_hits
  from question_activity qa
  left join agg_answers ag on ag.QuestionId = qa.QuestionId
  left join votes_agg va on va.PostId = qa.QuestionId
  left join tag_stats ta on ta.QuestionId = qa.QuestionId
),
ranked_questions as (
  select
    qq.QuestionId,
    qq.quality_bucket,
    qq.net_votes,
    qq.avg_answer_score,
    qq.has_accepted_answer,
    qq.sql_tag_hits,
    qa.views,
    qa.QScore,
    row_number() over (
      partition by qq.quality_bucket
      order by qq.net_votes desc, qa.views desc, qq.has_accepted_answer desc, qq.avg_answer_score desc, qq.sql_tag_hits desc, qq.QuestionId asc
    ) as rn_in_bucket
  from question_quality qq
  join question_activity qa on qa.QuestionId = qq.QuestionId
),
eligible_questions as (
  select rq.QuestionId
  from ranked_questions rq
  where rq.rn_in_bucket <= 100
),
final_scores as (
  select
    qp.QuestionId,
    qp.Title,
    os.DisplayName as OwnerName,
    os.Reputation,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.favorites,0) as favorites,
    coalesce(va.bounty_started,0) as bounty_started,
    coalesce(va.bounty_awarded,0) as bounty_awarded,
    qa.views,
    qa.QScore,
    coalesce(ag.total_answers,0) as total_answers,
    coalesce(ag.pos_answers,0) as pos_answers,
    coalesce(ag.neg_answers,0) as neg_answers,
    coalesce(cast(ag.avg_answer_score as numeric),0) as avg_answer_score,
    coalesce(ag.median_answer_score,0) as median_answer_score,
    ta.tags_sorted,
    coalesce(qe.edit_count,0) as edit_count,
    coalesce(dl.dup_links_out,0) as dup_links_out,
    qq.quality_bucket,
    (coalesce(va.upvotes,0) - coalesce(va.downvotes,0))
      + ln(1 + greatest(qa.views,0))
      + (case when qa.AcceptedAnswerId is not null then 2 else 0 end)
      + (coalesce(ag.avg_answer_score,0))
      + (coalesce(os.gold_badges,0) * 0.5 + coalesce(os.silver_badges,0) * 0.2 + coalesce(os.bronze_badges,0) * 0.1)
      - (coalesce(dl.dup_links_out,0) * 1.5)
      - (case when coalesce(qe.last_close_reason_id,0) in (101,102,103,104,105,1,2,3,4,7,10,20) then 3 else 0 end)
      as perf_score
  from q_posts qp
  left join votes_agg va on va.PostId = qp.QuestionId
  left join agg_answers ag on ag.QuestionId = qp.QuestionId
  left join question_edits qe on qe.QuestionId = qp.QuestionId
  left join dup_links dl on dl.QuestionId = qp.QuestionId
  left join tag_stats ta on ta.QuestionId = qp.QuestionId
  left join owner_stats os on os.UserId = qp.OwnerUserId
  left join question_activity qa on qa.QuestionId = qp.QuestionId
  left join question_quality qq on qq.QuestionId = qp.QuestionId
  where qp.QuestionId in (select QuestionId from eligible_questions)
),
dedup_aliases as (
  select
    fs.QuestionId,
    fs.Title,
    fs.OwnerName,
    fs.Reputation,
    fs.upvotes,
    fs.downvotes,
    fs.favorites,
    fs.bounty_started,
    fs.bounty_awarded,
    fs.views,
    fs.QScore,
    fs.total_answers,
    fs.pos_answers,
    fs.neg_answers,
    fs.avg_answer_score,
    fs.median_answer_score,
    fs.tags_sorted,
    fs.edit_count,
    fs.dup_links_out,
    fs.quality_bucket,
    fs.perf_score,
    case
      when fs.OwnerName is null or trim(fs.OwnerName) = '' then '(unknown)'
      when position(' ' in fs.OwnerName) = 0 then fs.OwnerName
      else split_part(fs.OwnerName, ' ', 1) || ' ' || upper(substr(split_part(fs.OwnerName, ' ', 2),1,1)) || '.'
    end as owner_alias
  from final_scores fs
),
with_nulls as (
  select
    da.QuestionId,
    da.Title,
    da.OwnerName,
    da.Reputation,
    da.upvotes,
    da.downvotes,
    da.favorites,
    da.bounty_started,
    da.bounty_awarded,
    da.views,
    da.QScore,
    da.total_answers,
    da.pos_answers,
    da.neg_answers,
    da.avg_answer_score,
    da.median_answer_score,
    da.tags_sorted,
    da.edit_count,
    da.dup_links_out,
    da.quality_bucket,
    da.perf_score,
    da.owner_alias,
    nullif(regexp_replace(coalesce(da.Title,''), '\s+', ' ', 'g'), '') as title_norm,
    case when da.tags_sorted is null or array_length(da.tags_sorted,1) = 0 then array['untagged'] else da.tags_sorted end as tags_norm
  from dedup_aliases da
)
select
  wn.QuestionId,
  wn.title_norm as Title,
  wn.owner_alias as OwnerAlias,
  wn.Reputation,
  wn.quality_bucket as Quality,
  wn.upvotes, wn.downvotes, wn.favorites,
  wn.views, wn.QScore,
  wn.total_answers, wn.pos_answers, wn.neg_answers,
  wn.avg_answer_score, wn.median_answer_score,
  wn.edit_count, wn.dup_links_out,
  wn.tags_norm as Tags,
  wn.perf_score,
  rank() over (order by wn.perf_score desc, wn.upvotes desc, wn.views desc) as PerfRankGlobal,
  dense_rank() over (partition by wn.quality_bucket order by wn.perf_score desc) as PerfRankInQuality
from with_nulls wn
where wn.perf_score is not null
order by wn.perf_score desc, wn.QuestionId asc
limit 250;