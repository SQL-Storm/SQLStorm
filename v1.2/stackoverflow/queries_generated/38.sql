-- {"query": "38.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1919} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
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
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        max(p.CreationDate) filter (where p.PostTypeId in (1,2)) as LastPostDate
    from Users u
    left join UserBadgeCounts ubc_gold on u.Id = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on u.Id = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on u.Id = ubc_bronze.UserId and ubc_bronze.Class = 3
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount
),
TopPostsWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        u.DisplayName as OwnerName,
        count(c.Id) as CommentCountReal,
        max(c.CreationDate) as LastCommentDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
    group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.AcceptedAnswerId, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.DisplayName
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwnerId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AnswerUpVotes,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as AnswerDownVotes,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount
    from Posts q
    join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
PostLinkDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        rank() over (order by u.Reputation desc) as ReputationRank,
        dense_rank() over (partition by date_trunc('year', u.CreationDate) order by u.Reputation desc) as YearlyRank
    from Users u
),
ComplexFilteredPosts as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        case
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered'
            else 'Open'
        end as PostStatus,
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) as TagCount,
        coalesce(p.FavoriteCount,0) + coalesce(p.CommentCount,0) as EngagementScore,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
      and p.Score > 5
      and p.ViewCount > 1000
      and (p.ClosedDate is null or p.ClosedDate > now() - interval '1 year')
      and (p.Tags like '%<sql>%' or p.Tags like '%<performance>%')
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.TotalPostScore,
    ua.LastPostDate,
    tpd.PostId as DuplicatePostId,
    tpd.RelatedPostId as OriginalPostId,
    tpd.PostTitle as DuplicatePostTitle,
    tpd.RelatedPostTitle as OriginalPostTitle,
    aas.QuestionTitle,
    aas.AnswerId,
    aas.AnswerScore,
    aas.AnswerOwnerName,
    aas.AnswerUpVotes,
    aas.AnswerDownVotes,
    aas.AnswerCommentCount,
    cfp.Title as PopularQuestionTitle,
    cfp.Score as PopularQuestionScore,
    cfp.ViewCount as PopularQuestionViews,
    cfp.TagCount as PopularQuestionTagCount,
    cfp.EngagementScore as PopularQuestionEngagement,
    urw.ReputationRank,
    urw.YearlyRank,
    rth.Level as TagHierarchyLevel,
    rth.Path as TagHierarchyPath
from UserActivity ua
left join PostLinkDuplicates tpd on tpd.PostId = ua.UserId
left join AcceptedAnswerStats aas on aas.AnswerOwnerId = ua.UserId
left join ComplexFilteredPosts cfp on cfp.OwnerUserId = ua.UserId
left join UserReputationWindow urw on urw.Id = ua.UserId
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(substring(cfp.Tags from 2 for length(cfp.Tags)-2), '><'))
where ua.Reputation > 1000
  and (ua.GoldBadges > 0 or ua.SilverBadges > 2)
order by ua.Reputation desc, cfp.Score desc nulls last
limit 100;