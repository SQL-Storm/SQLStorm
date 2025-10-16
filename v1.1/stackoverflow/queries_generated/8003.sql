-- {"query": "8003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3002} 
with
q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    p.AcceptedAnswerId,
    coalesce(nullif(trim(p.OwnerDisplayName), ''), u.DisplayName, '(unknown)') as OwnerName
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1
),
answers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn_by_score,
    count(*) over (partition by a.ParentId) as total_answers,
    max(a.Score) over (partition by a.ParentId) as max_answer_score
  from Posts a
  where a.PostTypeId = 2
),
accepted as (
  select
    q.QuestionId,
    a.AnswerId as AcceptedAnswerId,
    a.Score as AcceptedAnswerScore,
    a.CreationDate as AcceptedAnswerDate
  from q
  left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    max(case when v.VoteTypeId in (8,9) then v.BountyAmount else null end) as MaxBounty
  from Votes v
  group by v.PostId
),
comment_stats as (
  select
    c.PostId,
    count(*) as CommentCount,
    max(c.Score) as MaxCommentScore,
    min(c.CreationDate) as FirstCommentDate,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
post_edits as (
  select
    ph.PostId,
    sum(case when ph.PostHistoryTypeId in (4,5,6) then 1 else 0 end) as EditCount,
    max(case when ph.PostHistoryTypeId in (10) then 1 else 0 end) as WasClosed,
    max(case when ph.PostHistoryTypeId in (11) then 1 else 0 end) as WasReopened,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditDate
  from PostHistory ph
  group by ph.PostId
),
closure as (
  select
    ph.PostId,
    max(ph.CreationDate) as ClosedDate,
    max(case
          when ph.PostHistoryTypeId = 10 then
            nullif(regexp_replace(coalesce(ph.Comment, ''), '[^0-9]', '', 'g'), '')
        end) as CloseReasonIdText
  from PostHistory ph
  where ph.PostHistoryTypeId = 10
  group by ph.PostId
),
duplicates as (
  select
    pl.PostId as DuplicateOfPostId,
    pl.RelatedPostId as OriginalPostId,
    min(pl.CreationDate) as FirstDupLinkDate,
    count(*) as DupLinkCount
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId, pl.RelatedPostId
),
tags_expanded as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from q
),
tag_quality as (
  select
    te.QuestionId,
    array_agg(te.tag order by te.tag) as tag_list,
    count(*) as tag_count,
    sum(case when te.tag ilike '%sql%' then 1 else 0 end) as sql_tag_hits,
    sum(case when te.tag ilike '%java%' then 1 else 0 end) as java_tag_hits
  from tags_expanded te
  group by te.QuestionId
),
answer_rank as (
  select
    a.QuestionId,
    a.AnswerId,
    a.Score,
    dense_rank() over (partition by a.QuestionId order by a.Score desc) as score_rank,
    row_number() over (partition by a.QuestionId order by a.CreationDate asc) as chronological_rank
  from answers a
),
top_answer_per_q as (
  select distinct on (ar.QuestionId)
    ar.QuestionId,
    ar.AnswerId as TopAnswerId,
    ar.Score as TopAnswerScore
  from answer_rank ar
  order by ar.QuestionId, ar.score_rank
),
owner_stats as (
  select
    q.OwnerUserId,
    count(*) as QuestionsOwned,
    sum(q.Score) as TotalQScore,
    avg(q.ViewCount)::numeric(18,2) as AvgQViews,
    percentile_cont(0.9) within group (order by q.ViewCount) as P90QViews
  from q
  group by q.OwnerUserId
),
hotness as (
  select
    q.QuestionId,
    (coalesce(v.UpVotes,0) - coalesce(v.DownVotes,0))::numeric
      + ln(greatest(q.ViewCount, 1))::numeric
      + case when a.total_answers is not null then ln(greatest(a.total_answers,1)) else 0 end::numeric
      - extract(epoch from (now() - coalesce(q.CreationDate, now()))) / 86400.0 as HotScore
  from q
  left join votes_agg v on v.PostId = q.QuestionId
  left join (select QuestionId, max(total_answers) as total_answers from answers group by QuestionId) a on a.QuestionId = q.QuestionId
),
null_play as (
  select
    q.QuestionId,
    case
      when q.OwnerUserId is null then 'anon'
      when u.Reputation is null then 'no-rep'
      when u.Reputation >= 10000 then 'high'
      when u.Reputation >= 1000 then 'mid'
      else 'low'
    end as RepBucket,
    coalesce(u.UpVotes - u.DownVotes, 0) as NetUserVotes
  from q
  left join Users u on u.Id = q.OwnerUserId
),
activity_window as (
  select
    q.QuestionId,
    q.CreationDate,
    lead(q.CreationDate) over (order by q.CreationDate) as NextQuestionTime,
    lag(q.CreationDate) over (order by q.CreationDate) as PrevQuestionTime
  from q
),
cte_union as (
  select QuestionId from q where Score >= 10
  union
  select QuestionId from q where ViewCount >= 10000
),
cte_except as (
  select QuestionId from cte_union
  except
  select QuestionId from q where coalesce(ClosedDate, timestamp '1970-01-01') is not null
),
final as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.OwnerName,
    q.Score,
    q.ViewCount,
    q.CreationDate,
    tq.tag_list,
    tq.tag_count,
    coalesce(v.UpVotes,0) as UpVotes,
    coalesce(v.DownVotes,0) as DownVotes,
    coalesce(v.Favorites,0) as Favorites,
    coalesce(v.MaxBounty,0) as MaxBounty,
    cs.CommentCount,
    cs.MaxCommentScore,
    pe.EditCount,
    pe.WasClosed,
    pe.WasReopened,
    cl.ClosedDate,
    cl.CloseReasonIdText,
    acc.AcceptedAnswerId,
    acc.AcceptedAnswerScore,
    ta.TopAnswerId,
    ta.TopAnswerScore,
    a.total_answers,
    a.max_answer_score,
    os.QuestionsOwned,
    os.TotalQScore,
    os.AvgQViews,
    os.P90QViews,
    hp.HotScore,
    np.RepBucket,
    np.NetUserVotes,
    aw.NextQuestionTime,
    aw.PrevQuestionTime,
    coalesce(d.DupLinkCount,0) as DupLinkCount,
    case when d.OriginalPostId is not null then 1 else 0 end as IsMarkedDuplicate,
    case when tq.sql_tag_hits > 0 then 1 else 0 end as HasSqlTag,
    case when tq.java_tag_hits > 0 then 1 else 0 end as HasJavaTag,
    case
      when acc.AcceptedAnswerId is not null and ta.TopAnswerId = acc.AcceptedAnswerId then 'accepted_is_top'
      when acc.AcceptedAnswerId is not null then 'accepted_not_top'
      when ta.TopAnswerId is not null then 'no_accepted_but_has_top'
      else 'no_answers'
    end as AnswerSynopsis,
    case when q.Title ilike any (array['%help%','%urgent%','%please%']) then 1 else 0 end as HasPleaInTitle,
    length(coalesce(q.Title,'')) as TitleLen,
    position('?' in coalesce(q.Title,'')) as QMarkPos,
    case when q.Tags ilike '%<homework>%' then 1 else 0 end as IsHomeworkHint
  from q
  left join tag_quality tq on tq.QuestionId = q.QuestionId
  left join votes_agg v on v.PostId = q.QuestionId
  left join comment_stats cs on cs.PostId = q.QuestionId
  left join post_edits pe on pe.PostId = q.QuestionId
  left join closure cl on cl.PostId = q.QuestionId
  left join accepted acc on acc.QuestionId = q.QuestionId
  left join top_answer_per_q ta on ta.QuestionId = q.QuestionId
  left join (select QuestionId, max(total_answers) as total_answers, max(max_answer_score) as max_answer_score from answers group by QuestionId) a on a.QuestionId = q.QuestionId
  left join owner_stats os on os.OwnerUserId = q.OwnerUserId
  left join hotness hp on hp.QuestionId = q.QuestionId
  left join null_play np on np.QuestionId = q.QuestionId
  left join activity_window aw on aw.QuestionId = q.QuestionId
  left join (select DuplicateOfPostId, OriginalPostId, DupLinkCount from duplicates) d on d.DuplicateOfPostId = q.QuestionId
),
scored as (
  select
    f.*,
    (
      0.5 * coalesce(f.UpVotes,0)
      - 0.3 * coalesce(f.DownVotes,0)
      + 0.2 * coalesce(f.Favorites,0)
      + 0.001 * coalesce(f.ViewCount,0)
      + case when f.WasClosed = 1 then -5 else 0 end
      + case when f.IsMarkedDuplicate = 1 then -2 else 0 end
      + case when f.HasSqlTag = 1 then 1 else 0 end
      + case when f.HasJavaTag = 1 then 0.5 else 0 end
      + case when f.AnswerSynopsis = 'accepted_is_top' then 3
             when f.AnswerSynopsis = 'accepted_not_top' then 1
             when f.AnswerSynopsis = 'no_accepted_but_has_top' then 0.5
             else -1 end
      + least(5, coalesce(f.EditCount,0)) * 0.2
      + case when f.TitleLen between 15 and 120 then 1 else -0.5 end
      + case when f.QMarkPos > 0 then 0.2 else 0 end
      + case when f.HasPleaInTitle = 1 then -0.7 else 0 end
      + width_bucket(coalesce(f.HotScore,0), -50, 100, 10) * 0.1
    )::numeric(18,4) as CompositeScore
  from final f
),
ranked as (
  select
    s.*,
    row_number() over (order by s.CompositeScore desc, s.HotScore desc nulls last, s.ViewCount desc nulls last) as rn_global,
    rank() over (partition by s.RepBucket order by s.CompositeScore desc) as rn_by_bucket
  from scored s
)
select
  r.QuestionId,
  r.Title,
  r.OwnerUserId,
  r.OwnerName,
  r.Score,
  r.ViewCount,
  r.CreationDate,
  r.tag_list,
  r.UpVotes,
  r.DownVotes,
  r.Favorites,
  r.MaxBounty,
  r.CommentCount,
  r.EditCount,
  r.ClosedDate,
  r.AcceptedAnswerId,
  r.TopAnswerId,
  r.total_answers,
  r.HotScore,
  r.CompositeScore,
  r.rn_global,
  r.rn_by_bucket,
  r.RepBucket,
  r.AnswerSynopsis,
  r.DupLinkCount,
  r.IsMarkedDuplicate
from ranked r
where
  (r.QuestionId in (select QuestionId from cte_except)
   or r.CompositeScore > (
     select avg(CompositeScore) + stddev_pop(CompositeScore)
     from scored
   ))
  and (r.ClosedDate is null or r.WasReopened = 1)
  and coalesce(r.tag_count, 0) between 1 and 10
order by r.CompositeScore desc, r.HotScore desc nulls last, r.ViewCount desc nulls last
limit 250;