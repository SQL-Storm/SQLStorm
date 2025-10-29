-- {"query": "703.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2859} 
with
-- normalize tags into rows
q as (
  select
    p.Id as QuestionId,
    p.OwnerUserId as AskerId,
    p.CreationDate as QuestionCreation,
    p.Score as QuestionScore,
    p.ViewCount,
    p.AcceptedAnswerId,
    lower(trim(t)) as Tag
  from Posts p
  cross join lateral unnest(
    case
      when p.PostTypeId = 1 and p.Tags is not null and length(p.Tags) >= 2
        then string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
      else array[]::varchar[]
    end
  ) as t
  where p.PostTypeId = 1
),
-- answers joined and ranked by various quality signals
a as (
  select
    a.ParentId as QuestionId,
    a.Id as AnswerId,
    a.OwnerUserId as AnswererId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreation,
    count(distinct c.Id) filter (where c.Score > 0) as PosCommentCount,
    sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotes,
    max(case when v.VoteTypeId = 1 then 1 else 0 end) as IsAcceptedVote,
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn_by_score,
    row_number() over (partition by a.ParentId order by (coalesce(a.Score,0) + coalesce(sum(case when v.VoteTypeId=2 then 1 when v.VoteTypeId=3 then -1 else 0 end) over (partition by a.Id),0)) desc nulls last) as rn_by_net
  from Posts a
  left join Comments c on c.PostId = a.Id
  left join Votes v on v.PostId = a.Id and v.VoteTypeId in (1,2,3)
  where a.PostTypeId = 2
  group by a.ParentId, a.Id, a.OwnerUserId, a.Score, a.CreationDate
),
-- questions with close/duplicate signals and edit history
q_hist as (
  select
    ph.PostId as QuestionId,
    max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as WasClosed,
    max(case when ph.PostHistoryTypeId in (10) and ph.Comment ~ '^\s*(101|1)\s*$' then 1 else 0 end) as WasClosedAsDuplicate,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditDate,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount
  from PostHistory ph
  group by ph.PostId
),
-- user aggregates
u as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate as UserCreated,
    u.DisplayName,
    u.Location,
    coalesce(nullif(trim(split_part(coalesce(u.WebsiteUrl,''),'/',3)),''),'unknown') as Domain,
    sum(b.Class = 1::smallint)::int as GoldCount,
    sum(b.Class = 2::smallint)::int as SilverCount,
    sum(b.Class = 3::smallint)::int as BronzeCount,
    count(*) filter (where b.TagBased = 1) as TagBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.Location, Domain
),
-- tag stats
t as (
  select
    lower(TagName) as Tag,
    sum(Count) as TagCount,
    max(IsModeratorOnly::int) as IsModOnly,
    max(IsRequired::int) as IsRequired
  from Tags
  group by lower(TagName)
),
-- answerer engagement on the same tags before answering
answerer_prior as (
  select
    a.AnswerId,
    count(distinct p2.Id) as PriorAnswersSameTag,
    sum(case when p2.Score > 0 then 1 else 0 end) as PriorPosAnswersSameTag
  from a
  join Posts q1 on q1.Id = a.QuestionId and q1.PostTypeId = 1
  join q qt on qt.QuestionId = q1.Id
  join Posts p2 on p2.PostTypeId = 2 and p2.OwnerUserId = a.AnswererId and p2.CreationDate < a.AnswerCreation
  join Posts q2 on q2.Id = p2.ParentId and q2.PostTypeId = 1
  cross join lateral unnest(
    case
      when q2.Tags is not null and length(q2.Tags) >= 2
        then string_to_array(substring(q2.Tags, 2, length(q2.Tags)-2), '><')
      else array[]::varchar[]
    end
  ) as t2(tag2)
  where lower(t2.tag2) = qt.Tag
  group by a.AnswerId
),
-- question difficulty proxy from votes and views
q_signal as (
  select
    q.QuestionId,
    coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end),0) as QNetVotes,
    coalesce(max(p.ViewCount),0) as QViews,
    percentile_cont(0.5) within group (order by coalesce(p.Score,0)) over () as GlobalMedianScore
  from q
  join Posts p on p.Id = q.QuestionId
  left join Votes v on v.PostId = q.QuestionId and v.VoteTypeId in (2,3)
  group by q.QuestionId
),
-- dedupe tags per question to avoid fanout
q_tags as (
  select distinct QuestionId, Tag from q
),
-- accepted answer joins
accepted as (
  select
    p.Id as QuestionId,
    p.AcceptedAnswerId
  from Posts p
  where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
),
-- assemble core question-answer rows
qa as (
  select
    qt.QuestionId,
    qt.Tag,
    p.Title,
    p.CreationDate as QuestionCreation,
    p.Score as QuestionScore,
    p.ViewCount,
    qh.WasClosed,
    qh.WasClosedAsDuplicate,
    qh.EditCount,
    qh.FirstEditDate,
    a.AnswerId,
    a.AnswererId,
    a.AnswerScore,
    a.NetVotes,
    a.PosCommentCount,
    a.IsAcceptedVote,
    case when acc.AcceptedAnswerId = a.AnswerId then 1 else 0 end as IsAccepted,
    a.rn_by_score,
    a.rn_by_net
  from q_tags qt
  join Posts p on p.Id = qt.QuestionId
  left join q_hist qh on qh.QuestionId = qt.QuestionId
  left join a on a.QuestionId = qt.QuestionId
  left join accepted acc on acc.QuestionId = qt.QuestionId
),
-- windowed metrics per question and per tag
qa_w as (
  select
    qa.*,
    count(*) over (partition by qa.QuestionId) as AnswersPerQuestion,
    avg(coalesce(qa.AnswerScore,0)) over (partition by qa.QuestionId) as AvgAnswerScorePerQ,
    rank() over (partition by qa.QuestionId order by coalesce(qa.AnswerScore, -100000) desc nulls last, qa.AnswerId) as RankAnswerByScore,
    dense_rank() over (partition by qa.Tag order by coalesce(qa.QuestionScore, -100000) desc nulls last, qa.QuestionId) as DenseRankQByScoreInTag
  from qa
),
-- tag-level aggregates for normalization
tag_agg as (
  select
    qt.Tag,
    count(distinct qt.QuestionId) as TagQuestions,
    sum(case when p.Score > 0 then 1 else 0 end) as PosQ,
    avg(p.Score) as AvgQScore,
    percentile_cont(0.9) within group (order by p.ViewCount) as P90Views
  from q_tags qt
  join Posts p on p.Id = qt.QuestionId
  group by qt.Tag
),
-- final scored set with mixed constructs
scored as (
  select
    qw.*,
    t.TagCount,
    t.IsModOnly,
    t.IsRequired,
    ta.TagQuestions,
    ta.PosQ,
    ta.AvgQScore,
    ta.P90Views,
    up.Reputation as AskerRep,
    ua.Reputation as AnswererRep,
    coalesce(ap.PriorAnswersSameTag,0) as PriorAnswersSameTag,
    coalesce(ap.PriorPosAnswersSameTag,0) as PriorPosAnswersSameTag,
    qs.QNetVotes,
    qs.QViews,
    qs.GlobalMedianScore,
    -- composite difficulty/quality score with null-safe math and string ops
    (
      coalesce(qw.QuestionScore,0) * 0.35
      + coalesce(qw.AnswerScore,0) * 0.45
      + coalesce(qs.QNetVotes,0) * 0.15
      + case when qw.IsAccepted = 1 then 5 else 0 end
      - case when qw.WasClosed = 1 then 3 else 0 end
      + least(2, greatest(-2, ln(nullif(qw.ViewCount,0)::numeric)))::numeric
      + least(3, coalesce(ua.Reputation,0) / nullif(ta.AvgQScore,0.0001))::numeric
      + ln(1 + coalesce(ap.PriorAnswersSameTag,0))::numeric
      + case when position('c#' in coalesce(qw.Tag,'')) > 0 then 0.2 else 0 end
    ) as CompositeScore,
    -- text-based hash-ish score to stress string funcs
    md5(coalesce(left(coalesce(p.Title,''), 50) || ':' || qw.Tag, '')) as TitleTagSig
  from qa_w qw
  join Posts p on p.Id = qw.QuestionId
  left join t on t.Tag = qw.Tag
  left join tag_agg ta on ta.Tag = qw.Tag
  left join u up on up.UserId = p.OwnerUserId
  left join u ua on ua.UserId = qw.AnswererId
  left join answerer_prior ap on ap.AnswerId = qw.AnswerId
  left join q_signal qs on qs.QuestionId = qw.QuestionId
),
-- remove questions with extreme fanout using correlated subquery
pruned as (
  select s.*
  from scored s
  where (
    select count(distinct a2.AnswerId)
    from a a2
    where a2.QuestionId = s.QuestionId
  ) <= 50
)
-- final selection with set operations to introduce variety
select *
from (
  select
    s.QuestionId,
    s.AnswerId,
    s.Tag,
    s.TitleTagSig,
    s.CompositeScore,
    s.RankAnswerByScore,
    s.DenseRankQByScoreInTag,
    s.AnswersPerQuestion,
    s.AvgAnswerScorePerQ,
    s.AskerRep,
    s.AnswererRep,
    s.PriorAnswersSameTag,
    s.PriorPosAnswersSameTag,
    s.TagCount,
    s.TagQuestions,
    s.P90Views,
    s.QViews,
    s.WasClosed,
    s.WasClosedAsDuplicate,
    s.IsAccepted
  from pruned s
  where s.AnswerId is not null
    and (s.CompositeScore is null or s.CompositeScore between -1000 and 10000)
  union all
  select
    s.QuestionId,
    null as AnswerId,
    s.Tag,
    s.TitleTagSig,
    -9999.0 as CompositeScore, -- tag-only baseline rows
    null, null,
    s.AnswersPerQuestion,
    s.AvgAnswerScorePerQ,
    s.AskerRep,
    null as AnswererRep,
    0, 0,
    s.TagCount,
    s.TagQuestions,
    s.P90Views,
    s.QViews,
    s.WasClosed,
    s.WasClosedAsDuplicate,
    0 as IsAccepted
  from pruned s
  where not exists (
    select 1
    from pruned s2
    where s2.QuestionId = s.QuestionId
      and s2.AnswerId is not null
  )
) z
where coalesce(z.Tag,'') <> ''
qualify row_number() over (
  partition by z.QuestionId
  order by
    case when z.AnswerId is not null then 0 else 1 end,
    z.CompositeScore desc nulls last,
    z.AnswerId nulls last
) <= 5
order by z.CompositeScore desc nulls last, z.QuestionId, z.AnswerId nulls last
limit 500;