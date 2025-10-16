-- {"query": "621.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1279} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array_agg(p.Id) filter (where p.Id is not null) as PostIds
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    group by t.Id, t.TagName, t.Count
    union all
    select
        rtc.Id,
        rtc.TagName,
        rtc.Count,
        rtc.PostIds || array_agg(pl.RelatedPostId) filter (where pl.RelatedPostId is not null)
    from RecursiveTagCounts rtc
    join PostLinks pl on pl.PostId = any(rtc.PostIds)
    where array_length(rtc.PostIds, 1) < 1000
    group by rtc.Id, rtc.TagName, rtc.Count, rtc.PostIds
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        sum(v.VoteTypeId = 2::int)::int as UpVotesReceived,
        sum(v.VoteTypeId = 3::int)::int as DownVotesReceived,
        avg(p.Score) filter (where p.OwnerUserId = u.Id and p.Score is not null) as AvgPostScore,
        max(p.CreationDate) filter (where p.OwnerUserId = u.Id) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
ClosedQuestions as (
    select
        ph.PostId,
        max(ph.CreationDate) as ClosedDate,
        crt.Name as CloseReason
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserBadges as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        string_agg(b.Name, ', ' order by b.Date desc) as BadgeNames
    from Badges b
    group by b.UserId, b.Class
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as TotalAnswers,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when p.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAcceptedAnswer
    from Posts p
    join Posts q on q.Id = p.ParentId and q.PostTypeId = 1
    where p.PostTypeId = 2
    group by p.ParentId
),
UserPostHistoryEdits as (
    select
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        count(*) as EditCount
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.UserId, ph.PostId, ph.PostHistoryTypeId
)
select
    u.UserId,
    u.DisplayName,
    u.QuestionsAsked,
    u.AnswersGiven,
    u.CommentsMade,
    coalesce(ubGold.BadgeCount, 0) as GoldBadges,
    coalesce(ubSilver.BadgeCount, 0) as SilverBadges,
    coalesce(ubBronze.BadgeCount, 0) as BronzeBadges,
    u.UpVotesReceived,
    u.DownVotesReceived,
    u.AvgPostScore,
    u.LastPostDate,
    tq.Title as TopQuestionTitle,
    tq.Score as TopQuestionScore,
    tq.ViewCount as TopQuestionViews,
    cs.ClosedDate,
    cs.CloseReason,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.HasAcceptedAnswer,
    eh.EditCount as TotalEditsMade,
    case
        when u.AvgPostScore is null then 'No posts'
        when u.AvgPostScore > 10 then 'High quality'
        when u.AvgPostScore between 5 and 10 then 'Medium quality'
        else 'Low quality'
    end as QualityLabel
from UserActivity u
left join TopQuestions tq on tq.OwnerName = u.DisplayName and tq.rn = 1
left join ClosedQuestions cs on cs.PostId = tq.Id
left join AnswerStats ans on ans.QuestionId = tq.Id
left join UserBadges ubGold on ubGold.UserId = u.UserId and ubGold.Class = 1
left join UserBadges ubSilver on ubSilver.UserId = u.UserId and ubSilver.Class = 2
left join UserBadges ubBronze on ubBronze.UserId = u.UserId and ubBronze.Class = 3
left join (
    select UserId, sum(EditCount) as EditCount from UserPostHistoryEdits group by UserId
) eh on eh.UserId = u.UserId
where u.QuestionsAsked > 5
order by u.UpVotesReceived desc nulls last, u.QuestionsAsked desc
limit 100;