-- {"query": "87.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2762} 
with
q as (
  select
    p.Id as QuestionId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AcceptedAnswerId,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    u.Reputation,
    u.DisplayName,
    date_trunc('month', p.CreationDate) as MonthBucket
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1
    and p.CreationDate >= (select min(CreationDate) from Posts where PostTypeId = 1) + interval '365 days'
),
answers as (
  select
    a.ParentId as QuestionId,
    count(*) as TotalAnswers,
    sum(case when a.Score > 0 then 1 else 0 end) as PosAnswers,
    max(a.Score) as MaxAnswerScore,
    min(a.CreationDate) as FirstAnswerDate
  from Posts a
  where a.PostTypeId = 2
  group by a.ParentId
),
votes_agg as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as UpVotes,
    count(*) filter (where v.VoteTypeId = 3) as DownVotes,
    count(*) filter (where v.VoteTypeId = 5) as Favorites,
    count(*) filter (where v.VoteTypeId = 9) as BountyClosed,
    sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as BountyAmountTotal,
    min(v.CreationDate) filter (where v.VoteTypeId = 2) as FirstUpvoteAt
  from Votes v
  group by v.PostId
),
ph_closed as (
  select
    ph.PostId,
    min(ph.CreationDate) as FirstClosedAt,
    max(case when ph.Comment ~ '^[0-9]+$' then try_cast(ph.Comment as int) else null end) as CloseReasonIdNumeric,
    max(ph.Comment) as CloseReasonRaw
  from PostHistory ph
  where ph.PostHistoryTypeId = 10
  group by ph.PostId
),
dup_links as (
  select
    pl.PostId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
    min(pl.CreationDate) filter (where pl.LinkTypeId = 3) as FirstDupAt
  from PostLinks pl
  group by pl.PostId
),
tag_expansion as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from q
),
tag_stats as (
  select
    te.QuestionId,
    count(*) as TagCount,
    sum(case when lower(te.tag) in ('sql','postgresql','tsql','mysql') then 1 else 0 end) as SqlTagHits,
    string_agg(distinct lower(te.tag), '|') as TagsNormalized
  from tag_expansion te
  group by te.QuestionId
),
user_badges as (
  select
    b.UserId,
    count(*) as BadgesTotal,
    count(*) filter (where b.Class = 1) as GoldCount,
    count(*) filter (where b.Class = 2) as SilverCount,
    count(*) filter (where b.Class = 3) as BronzeCount,
    min(b.Date) as FirstBadgeDate
  from Badges b
  group by b.UserId
),
user_activity as (
  select
    u.Id as UserId,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate,
    u.LastAccessDate,
    extract(epoch from (u.LastAccessDate - u.CreationDate))/86400.0 as AccountAgeDays
  from Users u
),
q_enriched as (
  select
    q.*,
    a.TotalAnswers,
    a.PosAnswers,
    a.MaxAnswerScore,
    a.FirstAnswerDate,
    va.UpVotes as QUpVotes,
    va.DownVotes as QDownVotes,
    va.Favorites as QFavorites,
    va.BountyAmountTotal as QBountyAmount,
    va.FirstUpvoteAt,
    ph.FirstClosedAt,
    ph.CloseReasonIdNumeric,
    ph.CloseReasonRaw,
    dl.DuplicateLinks,
    dl.LinkedLinks,
    dl.FirstDupAt,
    ts.TagCount,
    ts.SqlTagHits,
    ts.TagsNormalized,
    ub.BadgesTotal,
    ub.GoldCount,
    ub.SilverCount,
    ub.BronzeCount,
    ua.Views as UserViews,
    ua.UpVotes as UserUpVotes,
    ua.DownVotes as UserDownVotes,
    ua.AccountAgeDays
  from q
  left join answers a on a.QuestionId = q.QuestionId
  left join votes_agg va on va.PostId = q.QuestionId
  left join ph_closed ph on ph.PostId = q.QuestionId
  left join dup_links dl on dl.PostId = q.QuestionId
  left join tag_stats ts on ts.QuestionId = q.QuestionId
  left join user_badges ub on ub.UserId = q.OwnerUserId
  left join user_activity ua on ua.UserId = q.OwnerUserId
),
accepted_answer_stats as (
  select
    aa.Id as AcceptedAnswerId,
    aa.ParentId as QuestionId,
    aa.Score as AcceptedScore,
    aa.CreationDate as AcceptedDate,
    va.UpVotes as AUpVotes,
    va.DownVotes as ADownVotes
  from Posts aa
  left join votes_agg va on va.PostId = aa.Id
  where aa.PostTypeId = 2
),
ranked_questions as (
  select
    qe.*,
    aas.AcceptedScore,
    aas.AUpVotes,
    aas.ADownVotes,
    case when qe.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    extract(epoch from (coalesce(qe.FirstAnswerDate, qe.LastActivityDate) - qe.CreationDate))/3600.0 as HoursToFirstAnswer,
    extract(epoch from (coalesce(qe.FirstClosedAt, qe.LastActivityDate) - qe.CreationDate))/3600.0 as HoursToCloseOrActivity,
    case
      when qe.ViewCount is null or qe.ViewCount = 0 then null
      else round((qe.Score::numeric / nullif(qe.ViewCount,0)) * 1000, 4)
    end as ScorePerKViews,
    case when qe.TagCount is null or qe.TagCount = 0 then 0 else qe.SqlTagHits::numeric / qe.TagCount end as SqlTagRatio
  from q_enriched qe
  left join accepted_answer_stats aas on aas.AcceptedAnswerId = qe.AcceptedAnswerId
),
monthly as (
  select
    MonthBucket,
    count(*) as Questions,
    avg(Score) as AvgScore,
    percentile_cont(0.5) within group (order by Score) as P50Score,
    avg(ViewCount) as AvgViews,
    avg(AnswerCount) as AvgAnswerCount,
    avg(case when HasAccepted=1 then 1 else 0 end) as AcceptedRate,
    avg(ScorePerKViews) as AvgScorePerKViews,
    avg(SqlTagRatio) as AvgSqlTagRatio
  from ranked_questions
  group by MonthBucket
),
user_influence as (
  select
    rq.OwnerUserId,
    count(*) as QCount,
    avg(rq.Score) as AvgQScore,
    sum(coalesce(rq.QFavorites,0)) as TotalFavorites,
    avg(coalesce(rq.HoursToFirstAnswer,0)) as AvgHoursToFirstAnswer,
    dense_rank() over (order by avg(rq.Score) desc nulls last) as RankByAvgScore
  from ranked_questions rq
  group by rq.OwnerUserId
),
extremes as (
  select
    rq.*,
    row_number() over (order by coalesce(rq.ScorePerKViews,-1) desc nulls last) as rn_best_spkv,
    row_number() over (order by coalesce(rq.ScorePerKViews,1e9)) as rn_worst_spkv,
    row_number() over (order by coalesce(rq.HoursToFirstAnswer,1e9)) as rn_fastest_answer,
    row_number() over (order by coalesce(rq.HoursToFirstAnswer,-1) desc nulls last) as rn_slowest_answer
  from ranked_questions rq
),
bench_base as (
  select
    rq.QuestionId,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.TagCount,
    rq.SqlTagRatio,
    rq.ScorePerKViews,
    rq.HoursToFirstAnswer,
    rq.HoursToCloseOrActivity,
    rq.QUpVotes,
    rq.QDownVotes,
    rq.QFavorites,
    rq.LinkedLinks,
    rq.DuplicateLinks,
    rq.CloseReasonIdNumeric,
    rq.CloseReasonRaw,
    rq.OwnerUserId,
    rq.Reputation,
    rq.BadgesTotal,
    rq.GoldCount,
    rq.SilverCount,
    rq.BronzeCount,
    rq.AccountAgeDays,
    ui.QCount as UserQCount,
    ui.AvgQScore as UserAvgQScore,
    ui.TotalFavorites as UserTotalFavorites,
    ui.RankByAvgScore as UserRankByAvgScore,
    m.AvgScore as MonthAvgScore,
    m.P50Score as MonthP50Score,
    m.AvgViews as MonthAvgViews,
    m.AvgAnswerCount as MonthAvgAnswers,
    m.AcceptedRate as MonthAcceptedRate
  from ranked_questions rq
  left join monthly m on m.MonthBucket = rq.MonthBucket
  left join user_influence ui on ui.OwnerUserId = rq.OwnerUserId
)
select
  bb.*,
  e.rn_best_spkv,
  e.rn_worst_spkv,
  e.rn_fastest_answer,
  e.rn_slowest_answer,
  case
    when coalesce(bb.TagCount,0) = 0 then 'untagged'
    when bb.SqlTagRatio >= 0.5 then 'sql-heavy'
    else 'mixed'
  end as TagProfile,
  case when bb.CloseReasonIdNumeric in (101,1) then 'duplicate'
       when bb.CloseReasonIdNumeric in (102,2) then 'off-topic'
       when bb.CloseReasonIdNumeric in (103) then 'needs details'
       when bb.CloseReasonIdNumeric in (104) then 'needs focus'
       when bb.CloseReasonIdNumeric in (105) then 'opinion-based'
       when bb.CloseReasonIdNumeric is null and bb.CloseReasonRaw is not null then 'closed-other'
       else 'open-or-unknown' end as CloseCategory,
  -- correlated subquery examples
  (
    select count(*) from Comments c
    where c.PostId = bb.QuestionId
      and c.Score > coalesce(bb.QUpVotes,0) - coalesce(bb.QDownVotes,0)
  ) as HighCommentCount,
  (
    select avg(c.Score)::numeric(10,2) from Comments c
    where c.PostId = bb.QuestionId
  ) as AvgCommentScore,
  -- set operator: union all to count interactions across posts and answers
  (
    select count(*) from (
      select v.Id from Votes v where v.PostId = bb.QuestionId
      union all
      select v2.Id from Votes v2
      join Posts a on a.Id = v2.PostId and a.ParentId = bb.QuestionId
    ) t
  ) as TotalVotesQAndAnswers
from bench_base bb
left join extremes e on e.QuestionId = bb.QuestionId
where
  (
    -- complex predicate mixing null logic
    coalesce(bb.ScorePerKViews, -1) > 0.5
    or (bb.SqlTagRatio >= 0.4 and coalesce(bb.AvgHoursToFirstAnswer,0) < 24)
    or (bb.UserRankByAvgScore is not null and bb.UserRankByAvgScore <= 100)
  )
  and (
    bb.CloseReasonIdNumeric is distinct from 105
    or bb.DuplicateLinks > 0
    or bb.QFavorites >= 1
  )
  and (
    -- string expressions
    lower(coalesce(bb.Title,'')) ~ '(sql|query|join|index)'
    or position('select' in lower(coalesce(bb.Title,''))) > 0
  )
order by
  e.rn_best_spkv nulls last,
  bb.Score desc nulls last
limit 500;