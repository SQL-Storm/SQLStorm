-- {"query": "262.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2989}
with recent_questions as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Title,
        q.Tags,
        coalesce(q.AnswerCount, 0) as AnswerCount,
        case when q.ClosedDate is null then 0 else 1 end as IsClosed
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore
    from Posts a
    where a.PostTypeId = 2
),
first_answer as (
    select
        a.QuestionId,
        min(a.AnswerCreationDate) as FirstAnswerDate
    from answers a
    group by a.QuestionId
),
votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal
    from Votes v
    group by v.PostId
),
comment_len as (
    select
        c.PostId,
        avg(length(c.Text)) as AvgCommentLen,
        count(*) as CommentCnt,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
post_edits as (
    select
        ph.PostId,
        sum(case when ph.PostHistoryTypeId in (4,5,6,7,8,9,24) then 1 else 0 end) as EditCount,
        max(case when ph.PostHistoryTypeId in (4,5,6,7,8,9,24) then ph.CreationDate end) as LastEditDate,
        sum(case when ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35) then 1 else 0 end) as ModActionCount
    from PostHistory ph
    group by ph.PostId
),
dup_links as (
    select
        pl.PostId as DuplicateOfId,
        count(*) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
tag_expansion as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag
    from recent_questions q
    where q.Tags is not null
),
tag_stats as (
    select
        te.QuestionId,
        avg(t.Count) as AvgTagPopularity,
        sum(case when coalesce(t.IsModeratorOnly, false) = true then 1 else 0 end) as ModOnlyTagCount,
        sum(case when coalesce(t.IsRequired, false) = true then 1 else 0 end) as RequiredTagCount,
        count(*) as TagCount
    from tag_expansion te
    left join Tags t on lower(t.TagName) = lower(te.tag)
    group by te.QuestionId
),
user_metrics as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes as UserUpVotes,
        u.DownVotes as UserDownVotes,
        u.Views as UserProfileViews,
        date_part('year', age(timestamp '2024-10-01 12:34:56', u.CreationDate)) as AccountAgeYears,
        coalesce(nullif(trim(coalesce(u.Location,'')), ''), 'Unknown') as NormLocation
    from Users u
),
question_owner as (
    select
        q.QuestionId,
        u.UserId,
        u.Reputation,
        u.AccountAgeYears,
        u.NormLocation,
        u.UserUpVotes,
        u.UserDownVotes,
        u.UserProfileViews
    from recent_questions q
    left join user_metrics u on u.UserId = q.OwnerUserId
),
answerer_diversity as (
    select
        a.QuestionId,
        count(distinct a.OwnerUserId) as DistinctAnswerers,
        avg(a.AnswerScore) as AvgAnswerScore
    from answers a
    group by a.QuestionId
),
accept_info as (
    select
        q.Id as QuestionId,
        case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
        q.AcceptedAnswerId
    from Posts q
    where q.PostTypeId = 1
),
accepted_answer_delay as (
    select
        ai.QuestionId,
        extract(epoch from (pa.CreationDate - pq.CreationDate))/3600.0 as HoursToAccept
    from accept_info ai
    join Posts pa on pa.Id = ai.AcceptedAnswerId
    join Posts pq on pq.Id = ai.QuestionId
),
question_activity as (
    select
        q.Id as QuestionId,
        q.CreationDate,
        q.LastActivityDate,
        coalesce(q.LastActivityDate, q.CreationDate) as LastAct,
        extract(epoch from (coalesce(q.LastActivityDate, q.CreationDate) - q.CreationDate))/3600.0 as HoursActive
    from Posts q
    where q.PostTypeId = 1
),
question_quality_score as (
    select
        rq.QuestionId,
        rq.Score,
        rq.ViewCount,
        coalesce(va.UpVotes,0) as UpVotes,
        coalesce(va.DownVotes,0) as DownVotes,
        coalesce(va.Favorites,0) as Favorites,
        coalesce(va.BountyTotal,0) as BountyTotal,
        coalesce(cs.CommentCnt,0) as CommentCnt,
        coalesce(cs.AvgCommentLen,0) as AvgCommentLen,
        coalesce(pe.EditCount,0) as EditCount,
        coalesce(pe.ModActionCount,0) as ModActionCount,
        coalesce(dl.DuplicateCount,0) as DuplicateCount,
        coalesce(ts.AvgTagPopularity,0) as AvgTagPopularity,
        coalesce(ts.TagCount,0) as TagCount
    from recent_questions rq
    left join votes_agg va on va.PostId = rq.QuestionId
    left join comment_len cs on cs.PostId = rq.QuestionId
    left join post_edits pe on pe.PostId = rq.QuestionId
    left join dup_links dl on dl.DuplicateOfId = rq.QuestionId
    left join tag_stats ts on ts.QuestionId = rq.QuestionId
),
rankings as (
    select
        qqs.QuestionId,
        dense_rank() over (order by qqs.Score desc nulls last, (qqs.UpVotes - qqs.DownVotes) desc) as RankByScore,
        dense_rank() over (order by qqs.ViewCount desc nulls last) as RankByViews,
        dense_rank() over (order by (qqs.Favorites + qqs.BountyTotal) desc nulls last) as RankByLove,
        ntile(10) over (order by (qqs.UpVotes - qqs.DownVotes) desc nulls last) as SentimentDecile
    from question_quality_score qqs
),
time_to_first_answer as (
    select
        rq.QuestionId,
        extract(epoch from (fa.FirstAnswerDate - rq.CreationDate))/3600.0 as HoursToFirstAnswer
    from recent_questions rq
    left join first_answer fa on fa.QuestionId = rq.QuestionId
),
nullability_checks as (
    select
        rq.QuestionId,
        case when rq.Tags is null or length(trim(both ' ' from rq.Tags)) = 0 then 1 else 0 end as IsTagNullOrEmpty,
        case when qo.Reputation is null then 1 else 0 end as IsOwnerMissing,
        case when qqs.UpVotes is null or qqs.DownVotes is null then 1 else 0 end as IsVoteDataMissing
    from recent_questions rq
    left join question_owner qo on qo.QuestionId = rq.QuestionId
    left join question_quality_score qqs on qqs.QuestionId = rq.QuestionId
),
owner_activity as (
    select
        qo.QuestionId,
        qo.UserId,
        qo.Reputation,
        qo.AccountAgeYears,
        sum(coalesce(p.Score,0)) as OwnerTotalPostScore,
        count(*) as OwnerPostCount
    from question_owner qo
    left join Posts p on p.OwnerUserId = qo.UserId
    group by qo.QuestionId, qo.UserId, qo.Reputation, qo.AccountAgeYears
),
final_scores as (
    select
        rq.QuestionId,
        rq.Title,
        rq.CreationDate,
        rq.IsClosed,
        qo.NormLocation as OwnerLocation,
        coalesce(oac.OwnerTotalPostScore,0) as OwnerTotalPostScore,
        coalesce(oac.OwnerPostCount,0) as OwnerPostCount,
        qqs.Score,
        qqs.ViewCount,
        qqs.UpVotes,
        qqs.DownVotes,
        qqs.Favorites,
        qqs.BountyTotal,
        qqs.CommentCnt,
        qqs.AvgCommentLen,
        qqs.EditCount,
        qqs.ModActionCount,
        qqs.DuplicateCount,
        qqs.AvgTagPopularity,
        qqs.TagCount,
        rnk.RankByScore,
        rnk.RankByViews,
        rnk.RankByLove,
        rnk.SentimentDecile,
        tfa.HoursToFirstAnswer,
        coalesce(aad.HoursToAccept, null) as HoursToAccept,
        qa.HoursActive,
        nc.IsTagNullOrEmpty,
        nc.IsOwnerMissing,
        nc.IsVoteDataMissing,
        (
            0.30 * coalesce(qqs.Score,0) +
            0.20 * greatest(0, coalesce(qqs.UpVotes,0) - coalesce(qqs.DownVotes,0)) +
            0.10 * coalesce(qqs.Favorites,0) +
            0.05 * coalesce(qqs.BountyTotal,0) +
            0.10 * least(10, coalesce(qqs.TagCount,0)) +
            0.05 * (coalesce(qqs.AvgTagPopularity,0) / nullif(coalesce(qqs.TagCount,1),0)) +
            0.05 * case when coalesce(qqs.DuplicateCount,0) = 0 then 1 else -1 end +
            0.05 * case when rq.IsClosed = 1 then -1 else 1 end +
            0.10 * case when coalesce(tfa.HoursToFirstAnswer, 99999) < 24 then 1 when coalesce(tfa.HoursToFirstAnswer, 99999) < 168 then 0.5 else 0 end
        ) as CompositeQualityScore
    from recent_questions rq
    left join question_owner qo on qo.QuestionId = rq.QuestionId
    left join owner_activity oac on oac.QuestionId = rq.QuestionId
    left join question_quality_score qqs on qqs.QuestionId = rq.QuestionId
    left join rankings rnk on rnk.QuestionId = rq.QuestionId
    left join time_to_first_answer tfa on tfa.QuestionId = rq.QuestionId
    left join accepted_answer_delay aad on aad.QuestionId = rq.QuestionId
    left join question_activity qa on qa.QuestionId = rq.QuestionId
    left join nullability_checks nc on nc.QuestionId = rq.QuestionId
),
location_rollup as (
    select
        fs.OwnerLocation,
        count(*) as QuestionsCount,
        avg(fs.CompositeQualityScore) as AvgCompositeQualityScore,
        stddev_pop(fs.CompositeQualityScore) as StdCompositeQualityScore,
        percentile_cont(0.9) within group (order by fs.CompositeQualityScore) as P90CompositeQualityScore
    from final_scores fs
    group by fs.OwnerLocation
),
top_locations as (
    select
        OwnerLocation
    from location_rollup
    where QuestionsCount >= 10
    order by AvgCompositeQualityScore desc
    limit 5
)
select
    fs.QuestionId,
    fs.Title,
    fs.CreationDate,
    fs.IsClosed,
    fs.OwnerLocation,
    fs.OwnerTotalPostScore,
    fs.OwnerPostCount,
    fs.Score,
    fs.ViewCount,
    fs.UpVotes,
    fs.DownVotes,
    fs.Favorites,
    fs.BountyTotal,
    fs.CommentCnt,
    fs.AvgCommentLen,
    fs.EditCount,
    fs.ModActionCount,
    fs.DuplicateCount,
    fs.AvgTagPopularity,
    fs.TagCount,
    fs.RankByScore,
    fs.RankByViews,
    fs.RankByLove,
    fs.SentimentDecile,
    fs.HoursToFirstAnswer,
    fs.HoursToAccept,
    fs.HoursActive,
    fs.IsTagNullOrEmpty,
    fs.IsOwnerMissing,
    fs.IsVoteDataMissing,
    fs.CompositeQualityScore,
    lr.AvgCompositeQualityScore as OwnerLocationAvgQuality,
    lr.StdCompositeQualityScore as OwnerLocationStdQuality,
    lr.P90CompositeQualityScore as OwnerLocationP90Quality
from final_scores fs
left join location_rollup lr on lr.OwnerLocation = fs.OwnerLocation
where fs.CompositeQualityScore is not null
  and (
      fs.OwnerLocation in (select OwnerLocation from top_locations)
      or fs.CompositeQualityScore >= (select percentile_cont(0.95) within group (order by CompositeQualityScore) from final_scores)
  )
order by fs.CompositeQualityScore desc, fs.ViewCount desc, fs.Score desc
limit 250;