-- {"query": "283.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1555} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and t.Count < r.Count and not t.TagName = any(r.Path)
    where r.Level < 3
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts p
    where p.PostTypeId in (1, 2)
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        a.ParentId,
        a.Body,
        a.CommentCount as AnswerCommentCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.Score > 10 and q.ViewCount > 1000
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner
    from PostLinks pl
    join Posts p on p.Id = pl.PostId
    join Users u on u.Id = p.OwnerUserId
    join Posts rp on rp.Id = pl.RelatedPostId
    join Users u2 on u2.Id = rp.OwnerUserId
    where pl.LinkTypeId = 3
),
CloseReasonsSummary as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes cht on cht.Id = ph.PostHistoryTypeId
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
UserActivitySummary as (
    select
        u.Id as UserId,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as Questions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as Answers,
        count(distinct c.Id) as CommentsMade,
        sum(vt.VoteCount) as TotalVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select
            v.PostId,
            count(*) as VoteCount
        from Votes v
        group by v.PostId
    ) vt on vt.PostId = p.Id
    group by u.Id
)
select
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LastBadgeDate,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.CommentsMade,
    ua.TotalVotesReceived,
    ur.ReputationRank,
    cr.CloseReason,
    cr.CloseCount,
    dt.TagName,
    dt.Count as TagCount,
    dt.Level as TagHierarchyLevel,
    dt.Path as TagPath,
    pq.QuestionId,
    pq.Title as QuestionTitle,
    pq.QuestionScore,
    pq.QuestionViews,
    pq.AnswerId,
    pq.AnswerScore,
    pq.AnswerCommentCount,
    pq.AnswerCreation,
    pq.AnswerOwnerUserId,
    pl.PostId as DuplicatePostId,
    pl.RelatedPostId as DuplicateRelatedPostId,
    pl.CreationDate as DuplicateLinkDate,
    pl.PostOwner as DuplicatePostOwner,
    pl.RelatedPostOwner as DuplicateRelatedPostOwner
from Users u
left join UserBadgeStats ub on ub.UserId = u.Id
left join UserActivitySummary ua on ua.UserId = u.Id
left join UserReputationRank ur on ur.Id = u.Id
left join CloseReasonsSummary cr on cr.CloseReason = (
    select cht.Name
    from PostHistory ph
    join PostHistoryTypes cht on cht.Id = ph.PostHistoryTypeId
    where ph.PostId in (
        select p.Id from Posts p where p.OwnerUserId = u.Id and p.ClosedDate is not null
    )
    order by ph.CreationDate desc limit 1
)
left join RecursiveTagHierarchy dt on dt.TagName = (
    select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'))
    from Posts p
    where p.OwnerUserId = u.Id and p.PostTypeId = 1
    order by p.CreationDate desc limit 1
)
left join TopQuestionsWithAnswers pq on pq.OwnerUserId = u.Id
left join DuplicateLinks pl on pl.PostOwner = u.DisplayName
where u.Reputation > 1000
order by ur.ReputationRank
limit 100;