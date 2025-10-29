-- {"query": "169.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2647} 
with recent_questions as (
    select
        q.Id as QuestionId,
        q.CreationDate as QuestionDate,
        q.OwnerUserId as AskerId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AcceptedAnswerId,
        date_trunc('month', q.CreationDate) as MonthBucket
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= now() - interval '730 days'
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswererId,
        a.CreationDate as AnswerDate,
        a.Score as AnswerScore
    from Posts a
    where a.PostTypeId = 2
),
first_answer as (
    select distinct on (a.QuestionId)
        a.QuestionId,
        a.AnswerId,
        a.AnswererId,
        a.AnswerDate,
        a.AnswerScore
    from answers a
    inner join recent_questions q on q.QuestionId = a.QuestionId
    order by a.QuestionId, a.AnswerDate asc, a.AnswerId
),
accepted_answer as (
    select
        q.QuestionId,
        q.AcceptedAnswerId,
        a.AnswererId as AcceptedAnswererId,
        a.AnswerDate as AcceptedAnswerDate,
        a.AnswerScore as AcceptedAnswerScore
    from recent_questions q
    left join answers a on a.AnswerId = q.AcceptedAnswerId
),
question_activity as (
    select
        q.QuestionId,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end), 0) as NetVotes,
        count(distinct c.Id) as CommentCount,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount
    from recent_questions q
    left join Votes v on v.PostId = q.QuestionId
    left join Comments c on c.PostId = q.QuestionId
    left join PostHistory ph on ph.PostId = q.QuestionId
    group by q.QuestionId
),
user_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate as UserCreation,
        u.UpVotes,
        u.DownVotes,
        u.Location,
        coalesce(nullif(trim(split_part(coalesce(u.WebsiteUrl, ''), '/', 3)), ''), 'unknown') as WebsiteHost,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, u.Location, WebsiteHost
),
tags_expanded as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as TagName
    from recent_questions q
),
tag_meta as (
    select
        te.QuestionId,
        te.TagName,
        t.Count as GlobalTagCount,
        t.IsModeratorOnly::int as IsModeratorOnly,
        t.IsRequired::int as IsRequired
    from tags_expanded te
    left join Tags t on lower(t.TagName) = lower(te.TagName)
),
dup_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks
    from PostLinks pl
    group by pl.PostId
),
close_events as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstCloseDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenDate,
        max(case when ph.PostHistoryTypeId = 10 then try_cast(ph.Comment as int) end) as LastCloseReasonId
    from PostHistory ph
    group by ph.PostId
),
fastest_answer as (
    select
        q.QuestionId,
        q.MonthBucket,
        fa.AnswerId,
        extract(epoch from (fa.AnswerDate - q.QuestionDate)) as SecsToFirstAnswer,
        aa.AcceptedAnswerId,
        case when aa.AcceptedAnswerId is not null and aa.AcceptedAnswerId = fa.AnswerId then 1 else 0 end as FirstWasAccepted
    from recent_questions q
    left join first_answer fa on fa.QuestionId = q.QuestionId
    left join accepted_answer aa on aa.QuestionId = q.QuestionId
),
question_rollup as (
    select
        q.QuestionId,
        q.MonthBucket,
        q.Title,
        q.Tags,
        q.QuestionScore,
        q.ViewCount,
        qa.NetVotes,
        qa.CommentCount,
        qa.EditCount,
        coalesce(dl.DuplicateLinks,0) as DuplicateLinks,
        coalesce(dl.LinkedLinks,0) as LinkedLinks,
        ce.FirstCloseDate,
        ce.LastReopenDate,
        ce.LastCloseReasonId,
        fa.SecsToFirstAnswer,
        fa.FirstWasAccepted
    from recent_questions q
    left join question_activity qa on qa.QuestionId = q.QuestionId
    left join dup_links dl on dl.QuestionId = q.QuestionId
    left join close_events ce on ce.QuestionId = q.QuestionId
    left join fastest_answer fa on fa.QuestionId = q.QuestionId
),
agg_by_tag as (
    select
        qr.MonthBucket,
        tm.TagName,
        count(distinct qr.QuestionId) as Questions,
        avg(nullif(qr.SecsToFirstAnswer,0)) as AvgSecsToFirstAnswer,
        percentile_cont(0.5) within group (order by qr.SecsToFirstAnswer) as MedianSecsToFirstAnswer,
        sum(qr.FirstWasAccepted) as FirstWasAcceptedCount,
        avg(qr.QuestionScore) as AvgQuestionScore,
        avg(qr.ViewCount) as AvgViews,
        avg(qr.NetVotes) as AvgNetVotes,
        avg(qr.CommentCount) as AvgComments,
        avg(qr.EditCount) as AvgEdits,
        sum(qr.DuplicateLinks) as DupLinks,
        sum(qr.LinkedLinks) as LinkLinks,
        max(tm.GlobalTagCount) as GlobalTagCount,
        max(tm.IsModeratorOnly) as AnyModOnly,
        max(tm.IsRequired) as AnyRequired
    from question_rollup qr
    join tag_meta tm on tm.QuestionId = qr.QuestionId
    group by qr.MonthBucket, tm.TagName
),
user_influence as (
    select
        q.QuestionId,
        uask.UserId as AskerId,
        uask.Reputation as AskerRep,
        ua.UserId as AnswererId,
        ua.Reputation as AnswererRep,
        coalesce(ua.GoldCount,0) as AnswererGold,
        coalesce(ua.SilverCount,0) as AnswererSilver,
        coalesce(ua.BronzeCount,0) as AnswererBronze,
        coalesce(uask.Location,'') as AskerLoc,
        coalesce(ua.Location,'') as AnswererLoc
    from recent_questions q
    left join user_stats uask on uask.UserId = q.AskerId
    left join first_answer fa on fa.QuestionId = q.QuestionId
    left join user_stats ua on ua.UserId = fa.AnswererId
),
norm as (
    select
        abt.MonthBucket,
        abt.TagName,
        abt.Questions,
        abt.AvgSecsToFirstAnswer,
        abt.MedianSecsToFirstAnswer,
        abt.FirstWasAcceptedCount,
        abt.AvgQuestionScore,
        abt.AvgViews,
        abt.AvgNetVotes,
        abt.AvgComments,
        abt.AvgEdits,
        abt.DupLinks,
        abt.LinkLinks,
        abt.GlobalTagCount,
        abt.AnyModOnly,
        abt.AnyRequired,
        row_number() over (partition by abt.MonthBucket order by abt.Questions desc, abt.AvgSecsToFirstAnswer nulls last) as rn_in_bucket
    from agg_by_tag abt
),
top_tags_per_month as (
    select *
    from norm
    where rn_in_bucket <= 10
),
cross_tag_influence as (
    select
        ttm.MonthBucket,
        ttm.TagName,
        count(distinct ui.AskerId) as DistinctAskers,
        count(distinct ui.AnswererId) as DistinctAnswerers,
        avg(nullif(ui.AnswererRep,0)) as AvgAnswererRep,
        avg(nullif(ui.AskerRep,0)) as AvgAskerRep,
        sum(case when ui.AnswererGold > 0 then 1 else 0 end) as AnswersByGoldUsers
    from top_tags_per_month ttm
    join tags_expanded te on te.TagName = ttm.TagName
    join user_influence ui on ui.QuestionId = te.QuestionId
    group by ttm.MonthBucket, ttm.TagName
),
final_rank as (
    select
        ttm.MonthBucket,
        ttm.TagName,
        ttm.Questions,
        ttm.AvgSecsToFirstAnswer,
        ttm.MedianSecsToFirstAnswer,
        ttm.FirstWasAcceptedCount,
        ttm.AvgQuestionScore,
        ttm.AvgViews,
        ttm.AvgNetVotes,
        ttm.AvgComments,
        ttm.AvgEdits,
        ttm.DupLinks,
        ttm.LinkLinks,
        ttm.GlobalTagCount,
        ttm.AnyModOnly,
        ttm.AnyRequired,
        cti.DistinctAskers,
        cti.DistinctAnswerers,
        cti.AvgAnswererRep,
        cti.AvgAskerRep,
        cti.AnswersByGoldUsers,
        dense_rank() over (
            partition by ttm.MonthBucket
            order by
                coalesce(ttm.Questions,0) desc,
                coalesce(ttm.FirstWasAcceptedCount,0) desc,
                coalesce(ttm.AvgViews,0) desc,
                coalesce(cti.AvgAnswererRep,0) desc,
                coalesce(ttm.AvgSecsToFirstAnswer,1e12) asc
        ) as RankInMonth
    from top_tags_per_month ttm
    left join cross_tag_influence cti
      on cti.MonthBucket = ttm.MonthBucket and cti.TagName = ttm.TagName
)
select
    to_char(fr.MonthBucket, 'YYYY-MM') as Month,
    fr.TagName,
    fr.RankInMonth,
    fr.Questions,
    round(fr.AvgSecsToFirstAnswer)::bigint as AvgSecsToFirstAnswer,
    round(fr.MedianSecsToFirstAnswer)::bigint as MedianSecsToFirstAnswer,
    fr.FirstWasAcceptedCount,
    round(fr.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    round(fr.AvgViews::numeric, 1) as AvgViews,
    round(fr.AvgNetVotes::numeric, 2) as AvgNetVotes,
    round(fr.AvgComments::numeric, 2) as AvgComments,
    round(fr.AvgEdits::numeric, 2) as AvgEdits,
    fr.DupLinks,
    fr.LinkLinks,
    fr.GlobalTagCount,
    fr.AnyModOnly,
    fr.AnyRequired,
    fr.DistinctAskers,
    fr.DistinctAnswerers,
    round(fr.AvgAnswererRep::numeric, 1) as AvgAnswererRep,
    round(fr.AvgAskerRep::numeric, 1) as AvgAskerRep,
    fr.AnswersByGoldUsers
from final_rank fr
where fr.RankInMonth <= 10
order by fr.MonthBucket desc, fr.RankInMonth, fr.TagName;