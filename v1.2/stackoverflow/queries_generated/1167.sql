-- {"query": "1167.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1532} 
with RecursiveTagCounts as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagAggregates as (
    select
        TagName,
        count(distinct PostId) as QuestionCount,
        sum(p.Score) as TotalScore,
        avg(p.ViewCount) as AvgViews,
        stddev_samp(p.Score) as ScoreStdDev
    from RecursiveTagCounts rtc
    join Posts p on p.Id = rtc.PostId
    group by TagName
),
UserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(b.BadgeCount, 0) as BadgeCount,
        max(v.TotalVotes) as MaxVotes,
        percentile_cont(0.5) within group (order by p.Score) as MedianPostScore
    from Users u
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) b on u.Id = b.UserId
    left join (
        select
            p.OwnerUserId as UserId,
            count(v.Id) as TotalVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        where p.OwnerUserId is not null
        group by p.OwnerUserId
    ) v on u.Id = v.UserId
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.BadgeCount
),
RankedPosts as (
    select
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc nulls last) as UserPostRank,
        dense_rank() over (order by p.Score desc nulls last) as GlobalScoreRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
ClosedQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.ClosedDate,
        cht.Name as CloseReason,
        ph.CreationDate as CloseVoteDate,
        ph.UserId as CloserUserId,
        (select count(*) from PostHistory ph2 where ph2.PostId = p.Id and ph2.PostHistoryTypeId = 10) as CloseVoteCount
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes cht on cht.Id::int = ph.Comment::int
    where p.ClosedDate is not null
    order by p.ClosedDate desc
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
ComplexUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(a.QuestionCount, 0) as QuestionsAsked,
        coalesce(a.AnswerCount, 0) as AnswersGiven,
        coalesce(c.CommentCount, 0) as CommentsMade,
        coalesce(l.LinkCount, 0) as PostLinksCreated,
        coalesce(ph.EditCount, 0) as EditsMade
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) a on u.Id = a.OwnerUserId
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) a2 on u.Id = a2.OwnerUserId
    left join (
        select UserId, count(*) as CommentCount
        from Comments
        group by UserId
    ) c on u.Id = c.UserId
    left join (
        select PostId, count(*) as LinkCount
        from PostLinks
        group by PostId
    ) l on l.PostId = u.Id
    left join (
        select UserId, count(*) as EditCount
        from PostHistory
        where PostHistoryTypeId in (4,5,6,7,8,9,14)
        group by UserId
    ) ph on u.Id = ph.UserId
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.BadgeCount,
    u.MaxVotes,
    u.MedianPostScore,
    r.GlobalScoreRank,
    r.UserPostRank,
    ra.AnswerCount,
    ra.AvgAnswerScore,
    ra.MaxAnswerScore,
    cq.CloseVoteCount,
    cq.CloseReason,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.EditsMade,
    tag.QuestionCount,
    tag.TotalScore,
    tag.AvgViews,
    tag.ScoreStdDev,
    case
        when u.MedianPostScore is null then 'No posts'
        when u.MedianPostScore > 10 then 'High median score'
        else 'Low median score'
    end as PostQualityCategory,
    coalesce(cq.ClosedDate, timestamp '1900-01-01') as ClosedDate,
    concat_ws(' | ',
        coalesce(cq.CloseReason, 'Open'),
        cast(ra.MaxAnswerScore as varchar),
        cast(u.MaxVotes as varchar)
    ) as SummaryString
from UserStats u
left join RankedPosts r on r.OwnerUserId = u.UserId and r.UserPostRank = 1
left join AnswerStats ra on ra.QuestionId = r.Id
left join ClosedQuestions cq on cq.Id = r.Id
left join ComplexUserActivity ua on ua.UserId = u.UserId
left join (
    select ta.UserId, sum(tag.QuestionCount) as QuestionCount, sum(tag.TotalScore) as TotalScore, avg(tag.AvgViews) as AvgViews, stddev_samp(tag.ScoreStdDev) as ScoreStdDev
    from (
        select
            rtc.TagName,
            count(distinct rtc.PostId) as QuestionCount,
            sum(p.Score) as TotalScore,
            avg(p.ViewCount) as AvgViews,
            stddev_samp(p.Score) as ScoreStdDev,
            p.OwnerUserId as UserId
        from RecursiveTagCounts rtc
        join Posts p on p.Id = rtc.PostId
        where p.OwnerUserId is not null
        group by rtc.TagName, p.OwnerUserId
    ) tag
    join Users ta on ta.Id = tag.UserId
    group by ta.UserId
) tag on tag.UserId = u.UserId
where u.Reputation > 1000
order by u.Reputation desc, u.BadgeCount desc;