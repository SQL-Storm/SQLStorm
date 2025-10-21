with recent_years as (
  select cast(extract(year from p.CreationDate) as int) as yr
  from Posts p
  where p.CreationDate is not null
  group by cast(extract(year from p.CreationDate) as int)
  order by yr desc
  limit 5
),
question_answers as (
  select
    q.Id as QuestionId,
    q.OwnerUserId as QuestionOwnerId,
    q.CreationDate as QuestionCreationDate,
    q.Score as QuestionScore,
    q.ViewCount as QuestionViews,
    q.Tags as QuestionTags,
    q.AcceptedAnswerId,
    a.Id as AnswerId,
    a.OwnerUserId as AnswerOwnerId,
    a.CreationDate as AnswerCreationDate,
    a.Score as AnswerScore
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
),
qa_enriched as (
  select
    qa.*,
    u_q.Reputation as QuestionOwnerRep,
    u_a.Reputation as AnswerOwnerRep
  from question_answers qa
  left join Users u_q on u_q.Id = qa.QuestionOwnerId
  left join Users u_a on u_a.Id = qa.AnswerOwnerId
),
qa_year_bucket as (
  select
    qa.QuestionId,
    qa.AnswerId,
    qa.AcceptedAnswerId,
    qa.QuestionScore,
    qa.QuestionViews,
    qa.AnswerScore,
    qa.QuestionOwnerRep,
    qa.AnswerOwnerRep,
    cast(extract(year from qa.QuestionCreationDate) as int) as QuestionYear,
    cast(extract(month from qa.QuestionCreationDate) as int) as QuestionMonth,
    coalesce(array_length(string_to_array(substring(qa.QuestionTags from 2 for length(qa.QuestionTags)-2), '><'), 1), 0) as TagCount
  from qa_enriched qa
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
    sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded
  from Votes v
  group by v.PostId
),
comments_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
links_agg as (
  select
    pl.PostId,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinks
  from PostLinks pl
  group by pl.PostId
),
history_events as (
  select
    ph.PostId,
    sum(case when ph.PostHistoryTypeId in (10,35) then 1 else 0 end) as CloseEvents,
    sum(case when ph.PostHistoryTypeId in (11) then 1 else 0 end) as ReopenEvents,
    sum(case when ph.PostHistoryTypeId in (12) then 1 else 0 end) as DeleteEvents,
    sum(case when ph.PostHistoryTypeId in (13) then 1 else 0 end) as UndeleteEvents,
    sum(case when ph.PostHistoryTypeId in (24) then 1 else 0 end) as SuggestedEditsApplied,
    count(*) as TotalHistoryEvents,
    max(ph.CreationDate) as LastHistoryEventDate
  from PostHistory ph
  group by ph.PostId
),
owner_activity as (
  select
    p.OwnerUserId as UserId,
    cast(extract(year from p.CreationDate) as int) as Yr,
    count(*) filter (where p.PostTypeId = 1) as QuestionsByYear,
    count(*) filter (where p.PostTypeId = 2) as AnswersByYear,
    sum(coalesce(p.Score,0)) as TotalScoreByYear
  from Posts p
  where p.OwnerUserId is not null
  group by p.OwnerUserId, cast(extract(year from p.CreationDate) as int)
),
owner_activity_recent as (
  select oa.UserId,
         sum(oa.QuestionsByYear) as QuestionsLast5Y,
         sum(oa.AnswersByYear) as AnswersLast5Y,
         sum(oa.TotalScoreByYear) as ScoreLast5Y
  from owner_activity oa
  join recent_years ry on ry.yr = oa.Yr
  group by oa.UserId
),
tag_extract as (
  select
    q.Id as QuestionId,
    unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as TagName
  from Posts q
  where q.PostTypeId = 1 and q.Tags is not null and q.Tags like '<%>'
),
top_tags as (
  select
    te.TagName,
    count(*) as TagUsage
  from tag_extract te
  group by te.TagName
  having count(*) >= 50
),
accepted_perf as (
  select
    qy.QuestionId,
    case when qy.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    a.CreationDate as AcceptedCreation,
    q.CreationDate as QuestionCreation,
    extract(epoch from (a.CreationDate - q.CreationDate)) as AcceptLatencySeconds
  from Posts q
  join qa_year_bucket qy on qy.QuestionId = q.Id
  left join Posts a on a.Id = qy.AcceptedAnswerId
),
final_rank as (
  select
    qy.QuestionId,
    qy.QuestionYear,
    qy.QuestionMonth,
    qy.TagCount,
    qy.QuestionScore,
    qy.QuestionViews,
    coalesce(va_q.UpVotes,0) as QUp,
    coalesce(va_q.DownVotes,0) as QDown,
    coalesce(va_q.Favorites,0) as QFav,
    coalesce(ca_q.CommentCount,0) as QComments,
    coalesce(ca_q.PositiveComments,0) as QPosComments,
    coalesce(la_q.LinkedCount,0) as QLinked,
    coalesce(la_q.DuplicateLinks,0) as QDupLinks,
    coalesce(he_q.CloseEvents,0) as QClosed,
    coalesce(he_q.ReopenEvents,0) as QReopened,
    coalesce(he_q.DeleteEvents,0) as QDeleted,
    ap.HasAccepted,
    ap.AcceptLatencySeconds,
    rank() over (
      partition by qy.QuestionYear
      order by (coalesce(va_q.UpVotes,0) - coalesce(va_q.DownVotes,0))*2
             + coalesce(va_q.Favorites,0)
             + coalesce(ca_q.CommentCount,0)*0.2
             + coalesce(la_q.LinkedCount,0)*0.5
             + coalesce(he_q.ReopenEvents,0)
             - coalesce(he_q.CloseEvents,0)*0.5
             + coalesce(qy.QuestionViews,0)/100.0
             + coalesce(qy.QuestionScore,0)*3
             + case when ap.HasAccepted = 1 then 5 else 0 end
             - coalesce(ap.AcceptLatencySeconds,0)/86400.0
    ) as PerfRankInYear
  from qa_year_bucket qy
  left join votes_agg va_q on va_q.PostId = qy.QuestionId
  left join comments_agg ca_q on ca_q.PostId = qy.QuestionId
  left join links_agg la_q on la_q.PostId = qy.QuestionId
  left join history_events he_q on he_q.PostId = qy.QuestionId
  left join accepted_perf ap on ap.QuestionId = qy.QuestionId
),
question_tag_score as (
  select
    te.QuestionId,
    sum(cast(TagUsage as numeric)) as TagPopularityScore
  from tag_extract te
  join top_tags tt on tt.TagName = te.TagName
  group by te.QuestionId
),
answer_stats as (
  select
    qa.QuestionId,
    count(distinct qa.AnswerId) as AnswerCount,
    max(qa.AnswerScore) as MaxAnswerScore,
    avg(qa.AnswerScore) filter (where qa.AnswerScore is not null) as AvgAnswerScore,
    sum(case when qa.AnswerScore > 0 then 1 else 0 end) as PositiveAnswers
  from qa_year_bucket qa
  group by qa.QuestionId
),
owners_recent as (
  select
    q.OwnerUserId as UserId,
    oa.QuestionsLast5Y,
    oa.AnswersLast5Y,
    oa.ScoreLast5Y
  from Posts q
  left join owner_activity_recent oa on oa.UserId = q.OwnerUserId
  where q.PostTypeId = 1
  group by q.OwnerUserId, oa.QuestionsLast5Y, oa.AnswersLast5Y, oa.ScoreLast5Y
),
scoreboard as (
  select
    fr.QuestionId,
    fr.QuestionYear,
    fr.QuestionMonth,
    fr.PerfRankInYear,
    fr.HasAccepted,
    fr.AcceptLatencySeconds,
    coalesce(qts.TagPopularityScore, 0) as TagPopularityScore,
    coalesce(ast.AnswerCount, 0) as AnswerCount,
    coalesce(ast.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(ast.AvgAnswerScore, 0.0) as AvgAnswerScore,
    coalesce(ast.PositiveAnswers, 0) as PositiveAnswers,
    fr.QUp, fr.QDown, fr.QFav, fr.QComments, fr.QPosComments, fr.QLinked, fr.QDupLinks,
    fr.QClosed, fr.QReopened, fr.QDeleted,
    fr.QuestionScore, fr.QuestionViews, fr.TagCount
  from final_rank fr
  left join question_tag_score qts on qts.QuestionId = fr.QuestionId
  left join answer_stats ast on ast.QuestionId = fr.QuestionId
),
per_year_summary as (
  select
    s.QuestionYear,
    count(*) as Questions,
    avg(s.QuestionViews) as AvgViews,
    avg(s.QuestionScore) as AvgQScore,
    avg(s.AvgAnswerScore) as AvgAScore,
    avg(s.AcceptLatencySeconds) filter (where s.HasAccepted = 1) as AvgAcceptLatencySec,
    percentile_cont(0.9) within group (order by s.QuestionViews) as P90Views,
    percentile_cont(0.9) within group (order by s.QuestionScore) as P90QScore
  from scoreboard s
  group by s.QuestionYear
)
select
  s.QuestionId,
  s.QuestionYear,
  s.QuestionMonth,
  s.PerfRankInYear,
  s.HasAccepted,
  round(s.AcceptLatencySeconds/3600.0, 2) as AcceptLatencyHours,
  s.TagPopularityScore,
  s.AnswerCount,
  s.MaxAnswerScore,
  round(s.AvgAnswerScore, 2) as AvgAnswerScore,
  s.PositiveAnswers,
  s.QUp, s.QDown, s.QFav, s.QComments, s.QPosComments, s.QLinked, s.QDupLinks,
  s.QClosed, s.QReopened, s.QDeleted,
  s.QuestionScore, s.QuestionViews, s.TagCount,
  pys.Questions as YearQuestions,
  round(pys.AvgViews, 2) as YearAvgViews,
  round(pys.AvgQScore, 2) as YearAvgQScore,
  round(pys.AvgAScore, 2) as YearAvgAScore,
  round(coalesce(pys.AvgAcceptLatencySec,0)/3600.0, 2) as YearAvgAcceptLatencyHours,
  pys.P90Views as YearP90Views,
  pys.P90QScore as YearP90QScore
from scoreboard s
join per_year_summary pys on pys.QuestionYear = s.QuestionYear
where s.PerfRankInYear <= 100
order by s.QuestionYear desc, s.PerfRankInYear asc, s.QuestionId asc;