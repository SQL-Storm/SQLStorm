-- {"query": "62.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1771} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 1 and not t2.Id = any(r.Path)
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
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        row_number() over (order by u.Reputation desc) as ReputationRank,
        rank() over (partition by u.Location order by u.Reputation desc) as LocationReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
TopPostsWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(vc.UpVotes, 0) as UpVotes,
        coalesce(vc.DownVotes, 0) as DownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by v.PostId
    ) vc on vc.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreator,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Users u on u.Id = (
        select OwnerUserId from Posts where Id = pl.PostId limit 1
    )
    where pl.LinkTypeId = 3
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserName
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where vt.Name = 'UpMod') as UpVotesGiven,
        count(distinct v.Id) filter (where vt.Name = 'DownMod') as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) as LastVoteDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id, u.DisplayName
),
TopUsersByActivity as (
    select
        uas.Id,
        uas.DisplayName,
        uas.QuestionsPosted,
        uas.AnswersPosted,
        uas.CommentsMade,
        uas.UpVotesGiven,
        uas.DownVotesGiven,
        uas.LastPostDate,
        uas.LastCommentDate,
        uas.LastVoteDate,
        (uas.QuestionsPosted + uas.AnswersPosted + uas.CommentsMade) as TotalContributions,
        row_number() over (order by (uas.QuestionsPosted + uas.AnswersPosted + uas.CommentsMade) desc) as ActivityRank
    from UserActivitySummary uas
    where (uas.QuestionsPosted + uas.AnswersPosted + uas.CommentsMade) > 50
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.TotalContributions,
    p.Id as TopPostId,
    p.Title as TopPostTitle,
    p.Score as TopPostScore,
    p.ViewCount as TopPostViews,
    p.CommentCount as TopPostComments,
    p.HasAcceptedAnswer,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.LinkTypeName as DuplicateLinkType,
    phcr.CloseReasonName,
    phcr.CloseDate,
    phcr.CloserName,
    rh.Level as TagHierarchyLevel,
    rh.TagName as RequiredTagName,
    rh.Count as TagUsageCount
from TopUsersByActivity ua
join UserReputationWindow u on u.Id = ua.Id
left join (
    select
        UserId,
        sum(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
        sum(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
        sum(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
    from UserBadgeCounts
    group by UserId
) ubc on ubc.UserId = u.Id
left join TopPostsWithComments p on p.OwnerUserId = u.Id and p.PostRank = 1
left join DuplicateLinks dl on dl.PostId = p.Id
left join PostHistoryCloseReasons phcr on phcr.PostId = p.Id
left join RecursiveTagHierarchy rh on rh.ExcerptPostId = p.Id or rh.WikiPostId = p.Id
where u.Reputation > 1000
order by ua.TotalContributions desc, u.Reputation desc
limit 100;