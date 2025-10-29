-- {"query": "2893.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1733}
with RecursiveTagCounts as (
    select
        p.Id as PostId,
        p.Title,
        p.OwnerUserId,
        unnest(string_to_array(substring(coalesce(p.Tags, '') from 2 for length(coalesce(p.Tags, '')) - 2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1
),
TagStats as (
    select
        t.Tag,
        count(*) as TotalPostsWithTag,
        avg(p.Score) as AvgScorePerTag,
        max(p.ViewCount) as MaxViewCountPerTag,
        count(distinct p.OwnerUserId) as UniqueAskersPerTag
    from RecursiveTagCounts t
    join Posts p on p.Id = t.PostId
    group by t.Tag
),
UserBadgeAggregates as (
    select 
        u.Id as UserId, 
        u.DisplayName,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) as LatestBadgeDate
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
AnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by a.ParentId) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
),
QuestionAndTopAnswerInfo as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        ar.AnswerId as TopAnswerId,
        coalesce(ar.Score, 0) as TopAnswerScore,
        coalesce(ua.DisplayName, 'unknown') as TopAnswererName,
        ua.Reputation as TopAnswererRep,
        q.ViewCount,
        q.Score as QuestionScore,
        q.AcceptedAnswerId,
        q.Tags
    from Posts q
    left join AnswerRanks ar on q.Id = ar.QuestionId and ar.AnswerRank = 1
    left join Users ua on ar.OwnerUserId = ua.Id
    where q.PostTypeId = 1
),
LatestPostHistoryEdits as (
    select ph.PostId,
        ph.UserId as EditorUserId,
        ph.CreationDate as EditDate,
        ph.PostHistoryTypeId,
        ph.Comment
    from (
        select ph.*,
            row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
        from PostHistory ph
        where ph.PostHistoryTypeId in (4,5,6)
    ) ph
    where ph.rn = 1
),
ClosedQuestions as (
    select ph.PostId, crt.Name as CloseReason, ph.CreationDate as ClosedAt
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
QuestionLinkInfo as (
    select
        q.Id as QuestionId,
        sum(case when lt.Name='Duplicate' then 1 else 0 end) as DuplicateCount,
        sum(case when lt.Name='Linked' then 1 else 0 end) as LinkedCount
    from Posts q
    left join PostLinks pl on q.Id = pl.PostId
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    where q.PostTypeId = 1
    group by q.Id
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsLast30Days,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersLast30Days,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc) as LastPostRank
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    group by u.Id, u.DisplayName
),
UserContentQuality as (
    select
        u.Id as UserId,
        coalesce(avg(p.Score),0) as AvgPostScore,
        coalesce(sum(p.ViewCount),0) as TotalViewsReceived,
        coalesce(sum(v.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(v.DownVotes), 0) as TotalDownVotes,
        count(distinct p.Id) as TotalPosts
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join (
        select PostId,
               sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
               sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on p.Id = v.PostId
    group by u.Id
)
select
    qti.QuestionId,
    qti.Title,
    qti.QuestionCreation as QuestionCreatedAt,
    qti.ViewCount,
    qti.QuestionScore,
    qti.AcceptedAnswerId,
    qti.TopAnswerId,
    qti.TopAnswerScore,
    qti.TopAnswererName,
    qti.TopAnswererRep,
    rtc.Tag,
    ts.TotalPostsWithTag,
    ts.AvgScorePerTag,
    ts.MaxViewCountPerTag,
    ts.UniqueAskersPerTag,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.LatestBadgeDate,
    lph.EditDate as LastEditDate,
    lph.EditorUserId,
    cq.CloseReason,
    cq.ClosedAt,
    qli.DuplicateCount,
    qli.LinkedCount,
    uaw.QuestionsLast30Days,
    uaw.AnswersLast30Days,
    uaw.LastPostRank,
    ucq.AvgPostScore,
    ucq.TotalViewsReceived,
    ucq.TotalUpVotes,
    ucq.TotalDownVotes,
    ucq.TotalPosts,
    case when position('sql' in coalesce(qti.Tags, '')) > 0 then 'Has SQL Tag' else 'No SQL Tag' end as SqlTagFlag,
    coalesce(nullif(qti.Title, ''), '[No Title]') || ' [' || coalesce(rtc.Tag, 'No Tag') || ']' as AnnotatedTitle
from QuestionAndTopAnswerInfo qti
left join RecursiveTagCounts rtc on rtc.PostId = qti.QuestionId
left join TagStats ts on ts.Tag = rtc.Tag
left join UserBadgeAggregates uba on uba.UserId = qti.TopAnswererRep
left join LatestPostHistoryEdits lph on lph.PostId = qti.QuestionId
left join ClosedQuestions cq on cq.PostId = qti.QuestionId
left join QuestionLinkInfo qli on qli.QuestionId = qti.QuestionId
left join UserActivityWindow uaw on uaw.UserId = qti.TopAnswererRep and uaw.LastPostRank = 1
left join UserContentQuality ucq on ucq.UserId = qti.TopAnswererRep
where qti.ViewCount > (
    select avg(ViewCount) from Posts where PostTypeId = 1
)
and (qti.QuestionScore + qti.TopAnswerScore) > (
    select percentile_cont(0.75) within group (order by Score) from Posts where PostTypeId in (1,2)
)
order by qti.ViewCount desc, qti.QuestionScore desc
limit 50;