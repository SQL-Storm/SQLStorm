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
    date_trunc('month', p.CreationDate) as MonthBucket,
    p.LastActivityDate
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
    count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
    count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
    count(case when v.VoteTypeId = 5 then 1 end) as Favorites,
    count(case when v.VoteTypeId = 9 then 1 end) as BountyClosed,
    sum(case when v.VoteTypeId in (8,9) then v.BountyAmount else 0 end) as BountyAmountTotal,
    min(case when v.VoteTypeId = 2 then v.CreationDate else null end) as FirstUpvoteAt
  from Votes v
  group by v.PostId
),
ph_closed as (
  select
    ph.PostId,
    min(ph.CreationDate) as FirstClosedAt,
    max(
      case
        when ph.Comment ~ '^[0-9]+$' then cast(ph.Comment as integer)
        else null
      end
    ) as CloseReasonIdNumeric,
    max(ph.Comment) as CloseReasonRaw
  from PostHistory ph
  where ph.PostHistoryTypeId = 10
  group by ph.PostId
),
dup_links as (
  select
    pl.PostId,
    count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateLinks,
    count(case when pl.LinkTypeId = 1 then 1 end) as LinkedLinks,
    min(case when pl.LinkTypeId = 3 then pl.CreationDate else null end) as FirstDupAt
  from PostLinks pl
  group by pl.PostId
),
tag_expansion as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(coalesce(q.Tags,''), 2, greatest(length(coalesce(q.Tags,''))-2,0)), '><')) as tag
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
    count(case when b.Class = 1 then 1 end) as GoldCount,
    count(case when b.Class = 2 then 1 end) as SilverCount,
    count(case when b.Class = 3 then 1 end) as BronzeCount,
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
    q.QuestionId,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.Title,
    q.Tags,
    q.AcceptedAnswerId,
    q.AnswerCount,
    q.Reputation,
    q.DisplayName,
    q.MonthBucket,
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
    ua.AccountAgeDays,
    q.LastActivityDate
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
    qe.QuestionId,
    qe.OwnerUserId,
    qe.CreationDate,
    qe.Score,
    qe.ViewCount,
    qe.Title,
    qe.Tags,
    qe.AcceptedAnswerId,
    qe.AnswerCount,
    qe.Reputation,
    qe.DisplayName,
    qe.MonthBucket,
    qe.TotalAnswers,
    qe.PosAnswers,
    qe.MaxAnswerScore,
    qe.FirstAnswerDate,
    qe.QUpVotes,
    qe.QDownVotes,
    qe.QFavorites,
    qe.QBountyAmount,
    qe.FirstUpvoteAt,
    qe.FirstClosedAt,
    qe.CloseReasonIdNumeric,
    qe.CloseReasonRaw,
    qe.DuplicateLinks,
    qe.LinkedLinks,
    qe.FirstDupAt,
    qe.TagCount,
    qe.SqlTagHits,
    qe.TagsNormalized,
    qe.BadgesTotal,
    qe.GoldCount,
    qe.SilverCount,
    qe.BronzeCount,
    qe.UserViews,
    qe.UserUpVotes,
    qe.UserDownVotes,
    qe.AccountAgeDays,
    qe.LastActivityDate,
    aas.AcceptedScore,
    aas.AUpVotes,
    aas.ADownVotes,
    case when qe.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    extract(epoch from (coalesce(qe.FirstAnswerDate, qe.LastActivityDate) - qe.CreationDate))/3600.0 as HoursToFirstAnswer,
    extract(epoch from (coalesce(qe.FirstClosedAt, qe.LastActivityDate) - qe.CreationDate))/3600.0 as HoursToCloseOrActivity,
    case
      when qe.ViewCount is null or qe.ViewCount = 0 then null
      else round((cast(qe.Score as numeric) / nullif(qe.ViewCount,0)) * 1000, 4)
    end as ScorePerKViews,
    case when qe.TagCount is null or qe.TagCount = 0 then 0 else cast(qe.SqlTagHits as numeric) / qe.TagCount end as SqlTagRatio
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
    rq.QuestionId,
    rq.Score,
    rq.ScorePerKViews,
    rq.HoursToFirstAnswer,
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
    m.AcceptedRate as MonthAcceptedRate,
    rq.LastActivityDate
  from ranked_questions rq
  left join monthly m on m.MonthBucket = rq.MonthBucket
  left join user_influence ui on ui.OwnerUserId = rq.OwnerUserId
)
select
  bb.QuestionId,
  bb.Title,
  bb.Score,
  bb.ViewCount,
  bb.AnswerCount,
  bb.TagCount,
  bb.SqlTagRatio,
  bb.ScorePerKViews,
  bb.HoursToFirstAnswer,
  bb.HoursToCloseOrActivity,
  bb.QUpVotes,
  bb.QDownVotes,
  bb.QFavorites,
  bb.LinkedLinks,
  bb.DuplicateLinks,
  bb.CloseReasonIdNumeric,
  bb.CloseReasonRaw,
  bb.OwnerUserId,
  bb.Reputation,
  bb.BadgesTotal,
  bb.GoldCount,
  bb.SilverCount,
  bb.BronzeCount,
  bb.AccountAgeDays,
  bb.UserQCount,
  bb.UserAvgQScore,
  bb.UserTotalFavorites,
  bb.UserRankByAvgScore,
  bb.MonthAvgScore,
  bb.MonthP50Score,
  bb.MonthAvgViews,
  bb.MonthAvgAnswers,
  bb.MonthAcceptedRate,
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
  (
    select count(*) from Comments c
    where c.PostId = bb.QuestionId
      and c.Score > coalesce(bb.QUpVotes,0) - coalesce(bb.QDownVotes,0)
  ) as HighCommentCount,
  (
    select cast(avg(c.Score) as numeric(10,2)) from Comments c
    where c.PostId = bb.QuestionId
  ) as AvgCommentScore,
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
    coalesce(bb.ScorePerKViews, -1) > 0.5
    or (bb.SqlTagRatio >= 0.4 and coalesce(bb.UserAvgQScore,0) is not distinct from coalesce(bb.UserAvgQScore,0) and coalesce(bb.UserAvgQScore,0) >= 0 and coalesce(bb.UserAvgQScore,0) < 999999) -- placeholder to keep dialects happy
    or (bb.UserRankByAvgScore is not null and bb.UserRankByAvgScore <= 100)
  )
  and (
    not (bb.CloseReasonIdNumeric = 105)
    or coalesce(bb.DuplicateLinks,0) > 0
    or coalesce(bb.QFavorites,0) >= 1
  )
  and (
    lower(coalesce(bb.Title,'')) ~ '(sql|query|join|index)'
    or position('select' in lower(coalesce(bb.Title,''))) > 0
  )
order by
  e.rn_best_spkv nulls last,
  bb.Score desc nulls last
limit 500;