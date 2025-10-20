with recent_questions as (
    select p.Id as QuestionId,
           p.CreationDate,
           p.Score,
           p.OwnerUserId,
           p.ViewCount,
           p.AnswerCount,
           p.Tags,
           p.Title
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
question_tags as (
    select q.QuestionId,
           unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as Tag
    from recent_questions q
    where q.Tags is not null and q.Tags <> ''
),
top_tags as (
    select qt.Tag,
           count(*) as QCount,
           sum(case when rq.Score >= 5 then 1 else 0 end) as HotQuestions,
           sum(rq.ViewCount) as TotalViews
    from question_tags qt
    join recent_questions rq on rq.QuestionId = qt.QuestionId
    group by qt.Tag
    having count(*) >= 50
),
answers as (
    select a.Id as AnswerId,
           a.ParentId as QuestionId,
           a.OwnerUserId as AnswererId,
           a.Score as AnswerScore,
           a.CreationDate as AnswerDate
    from Posts a
    where a.PostTypeId = 2
),
first_answers as (
    select a.QuestionId,
           min(a.AnswerDate) as FirstAnswerDate
    from answers a
    group by a.QuestionId
),
accepts as (
    select q.Id as QuestionId,
           q.AcceptedAnswerId
    from Posts q
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
answer_counts as (
    select a.QuestionId,
           count(*) as AnswerTotal,
           sum(case when a.AnswerScore >= 1 then 1 else 0 end) as UpvotedAnswers
    from answers a
    group by a.QuestionId
),
question_activity as (
    select rq.QuestionId,
           rq.CreationDate,
           rq.Score,
           rq.ViewCount,
           rq.AnswerCount,
           ac.AnswerTotal,
           ac.UpvotedAnswers,
           fa.FirstAnswerDate,
           extract(epoch from (fa.FirstAnswerDate - rq.CreationDate))/3600.0 as HoursToFirstAnswer,
           case when acc.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted
    from recent_questions rq
    left join answer_counts ac on ac.QuestionId = rq.QuestionId
    left join first_answers fa on fa.QuestionId = rq.QuestionId
    left join accepts acc on acc.QuestionId = rq.QuestionId
),
question_votes as (
    select v.PostId as QuestionId,
           sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
           sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
           sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
           sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
           sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded
    from Votes v
    join recent_questions rq on rq.QuestionId = v.PostId
    group by v.PostId
),
comment_engagement as (
    select c.PostId as QuestionId,
           count(*) as CommentCount,
           sum(case when c.Score >= 1 then 1 else 0 end) as HelpfulComments,
           max(c.CreationDate) as LastCommentAt
    from Comments c
    join recent_questions rq on rq.QuestionId = c.PostId
    group by c.PostId
),
post_links as (
    select pl.PostId as QuestionId,
           sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
           sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateFlags
    from PostLinks pl
    join recent_questions rq on rq.QuestionId = pl.PostId
    group by pl.PostId
),
edit_events as (
    select ph.PostId as QuestionId,
           count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditCount,
           count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20)) as ModEvents,
           max(ph.CreationDate) as LastEditAt
    from PostHistory ph
    join recent_questions rq on rq.QuestionId = ph.PostId
    group by ph.PostId
),
user_stats as (
    select u.Id as UserId,
           u.Reputation,
           u.UpVotes,
           u.DownVotes,
           u.Views
    from Users u
),
question_owner as (
    select rq.QuestionId,
           u.Reputation as OwnerReputation,
           u.UpVotes as OwnerUpVotes,
           u.DownVotes as OwnerDownVotes,
           u.Views as OwnerProfileViews
    from recent_questions rq
    left join Users u on u.Id = rq.OwnerUserId
),
tag_density as (
    select qt.QuestionId,
           count(*) as TagCount
    from question_tags qt
    group by qt.QuestionId
),
aggregated as (
    select qt.Tag,
           count(distinct qa.QuestionId) as Questions,
           avg(qa.Score) as AvgScore,
           percentile_cont(0.5) within group (order by qa.Score) as MedianScore,
           avg(qa.ViewCount) as AvgViews,
           percentile_cont(0.5) within group (order by qa.ViewCount) as MedianViews,
           avg(coalesce(qv.UpVotes,0)) as AvgUpVotes,
           avg(coalesce(qv.DownVotes,0)) as AvgDownVotes,
           avg(coalesce(qv.Favorites,0)) as AvgFavorites,
           avg(coalesce(qv.BountyAwarded,0)) as AvgBountyAwarded,
           avg(coalesce(qa.HoursToFirstAnswer, 24*7)) as AvgHoursToFirstAnswer,
           cast(sum(case when qa.HasAccepted = 1 then 1 else 0 end) as float) / nullif(count(*),0) as AcceptRate,
           avg(coalesce(ac.TagCount,0)) as AvgTagCount,
           avg(coalesce(ce.CommentCount,0)) as AvgComments,
           avg(coalesce(ce.HelpfulComments,0)) as AvgHelpfulComments,
           avg(coalesce(pl.DuplicateFlags,0)) as AvgDuplicateFlags,
           avg(coalesce(ee.EditCount,0)) as AvgEdits,
           avg(coalesce(ee.ModEvents,0)) as AvgModEvents,
           percentile_cont(0.9) within group (order by qa.ViewCount) as P90Views,
           percentile_cont(0.9) within group (order by qa.Score) as P90Score
    from question_tags qt
    join question_activity qa on qa.QuestionId = qt.QuestionId
    left join question_votes qv on qv.QuestionId = qt.QuestionId
    left join tag_density ac on ac.QuestionId = qt.QuestionId
    left join comment_engagement ce on ce.QuestionId = qt.QuestionId
    left join post_links pl on pl.QuestionId = qt.QuestionId
    left join edit_events ee on ee.QuestionId = qt.QuestionId
    group by qt.Tag
),
top_users as (
    select qt.Tag,
           u.Id as UserId,
           u.DisplayName,
           sum(case when p.PostTypeId = 1 then greatest(p.Score,0) else 0 end) as QScore,
           sum(case when p.PostTypeId = 2 then greatest(p.Score,0) else 0 end) as AScore,
           count(*) filter (where p.PostTypeId = 1) as QCount,
           count(*) filter (where p.PostTypeId = 2) as ACount,
           row_number() over (partition by qt.Tag order by sum(greatest(p.Score,0)) desc, count(*) desc) as rn
    from question_tags qt
    join Posts q on q.Id = qt.QuestionId
    join Posts p on p.OwnerUserId = q.OwnerUserId
    join Users u on u.Id = q.OwnerUserId
    where p.PostTypeId in (1,2)
    group by qt.Tag, u.Id, u.DisplayName
),
tag_rank as (
    select a.*,
           dense_rank() over (order by a.Questions desc, a.AvgViews desc, a.AvgScore desc) as TagRank
    from aggregated a
    join top_tags t on t.Tag = a.Tag
)
select tr.Tag,
       tr.Questions,
       round(cast(tr.AvgScore as numeric), 2) as AvgScore,
       round(cast(tr.MedianScore as numeric), 2) as MedianScore,
       round(cast(tr.AvgViews as numeric), 2) as AvgViews,
       round(cast(tr.MedianViews as numeric), 2) as MedianViews,
       round(cast(tr.AvgUpVotes as numeric), 2) as AvgUpVotes,
       round(cast(tr.AvgDownVotes as numeric), 2) as AvgDownVotes,
       round(cast(tr.AvgFavorites as numeric), 2) as AvgFavorites,
       round(cast(tr.AvgBountyAwarded as numeric), 2) as AvgBountyAwarded,
       round(cast(tr.AvgHoursToFirstAnswer as numeric), 2) as AvgHoursToFirstAnswer,
       round(cast(tr.AcceptRate as numeric), 4) as AcceptRate,
       round(cast(tr.AvgTagCount as numeric), 2) as AvgTagCount,
       round(cast(tr.AvgComments as numeric), 2) as AvgComments,
       round(cast(tr.AvgHelpfulComments as numeric), 2) as AvgHelpfulComments,
       round(cast(tr.AvgDuplicateFlags as numeric), 2) as AvgDuplicateFlags,
       round(cast(tr.AvgEdits as numeric), 2) as AvgEdits,
       round(cast(tr.AvgModEvents as numeric), 2) as AvgModEvents,
       tr.P90Views,
       tr.P90Score,
       tu.DisplayName as TopContributor,
       tu.QScore + tu.AScore as TopContributorTotalScore,
       tu.QCount as TopContributorQCount,
       tu.ACount as TopContributorACount,
       tr.TagRank
from tag_rank tr
left join lateral (
    select DisplayName, QScore, AScore, QCount, ACount
    from top_users tu
    where tu.Tag = tr.Tag and tu.rn = 1
) tu on true
order by tr.TagRank, tr.Tag
limit 100;