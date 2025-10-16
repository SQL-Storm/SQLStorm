-- {"query": "107.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1508} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id > r.Id and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        row_number() over (partition by u.Location order by u.Reputation desc nulls last) as RepRankInLocation,
        count(*) over (partition by u.Location) as UsersInLocation
    from Users u
    where u.Location is not null
),
PostScoreStats as (
    select
        p.OwnerUserId,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        count(*) as PostCount
    from Posts p
    where p.PostTypeId in (1, 2) and p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        a.OwnerUserId as AnswerOwner,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by q.Id order by a.Score desc nulls last, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.Score > 10 and q.ViewCount > 1000
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived,
        coalesce(sum(bc.BadgeCount), 0) as TotalBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join (
        select UserId, sum(BadgeCount) as BadgeCount from UserBadgeCounts group by UserId
    ) bc on bc.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
ComplexFilteredPosts as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.Comment,
        ph.Text as HistoryText,
        row_number() over (partition by p.Id order by ph.CreationDate desc) as HistoryRank
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6)
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 5 and p.ViewCount > 500
      and (p.Tags like '%<sql>%' or p.Tags like '%<database>%')
      and (ph.Comment is null or ph.Comment not like '%rollback%')
)
select
    u.DisplayName as User,
    u.Location,
    u.Reputation,
    urs.RepRankInLocation,
    urs.UsersInLocation,
    pas.AvgScore,
    pas.MaxScore,
    pas.MinScore,
    pas.PostCount,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.CommentsMade,
    uas.UpVotesReceived,
    uas.DownVotesReceived,
    uas.TotalBadges,
    dt.TagName as SampleTag,
    dt.Count as TagUsageCount,
    dq.PostTitle as DuplicateQuestion,
    dq.RelatedPostTitle as DuplicateOf,
    cq.Title as RecentQuestionTitle,
    cq.Score as RecentQuestionScore,
    cq.ViewCount as RecentQuestionViews,
    cq.HistoryText as RecentEditSummary,
    cq.HistoryDate as RecentEditDate,
    cq.HistoryRank as EditRank
from Users u
join UserReputationWindow urs on urs.Id = u.Id
left join PostScoreStats pas on pas.OwnerUserId = u.Id
left join UserActivitySummary uas on uas.UserId = u.Id
left join RecursiveTagHierarchy dt on dt.Level = 1
left join DuplicateLinks dq on dq.PostId = (
    select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by p.CreationDate desc limit 1
)
left join ComplexFilteredPosts cq on cq.OwnerUserId = u.Id and cq.HistoryRank = 1
where u.Reputation > 1000 and urs.RepRankInLocation <= 5
order by u.Reputation desc, uas.TotalBadges desc
limit 50;