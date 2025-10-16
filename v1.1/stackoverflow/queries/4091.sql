with RecursiveBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, b.Class
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.AcceptedAnswerId,
        row_number() over(partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserPostRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
TopUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        rbc.BadgeCountGold,
        rbc.BadgeCountSilver,
        rbc.BadgeCountBronze,
        coalesce(pq.QuestionCount, 0) as QuestionCount,
        coalesce(pa.AnswerCount, 0) as AnswerCount,
        coalesce(fav.FavoritePosts, 0) as FavoritesCount
    from Users u
    left join (
        select
            UserId,
            sum(case when Class=1 then BadgeCount else 0 end) as BadgeCountGold,
            sum(case when Class=2 then BadgeCount else 0 end) as BadgeCountSilver,
            sum(case when Class=3 then BadgeCount else 0 end) as BadgeCountBronze
        from RecursiveBadgeCounts
        group by UserId
    ) rbc on rbc.UserId = u.Id
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) pq on pq.OwnerUserId = u.Id
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) pa on pa.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as FavoritePosts
        from Votes v
        where v.VoteTypeId = 5 and UserId is not null
        group by UserId
    ) fav on fav.UserId = u.Id
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwnerId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.Body as AnswerBody,
        exists (
            select 1
            from Votes v
            where v.PostId = a.Id
              and v.VoteTypeId = 3
        ) as AnswerHasDownvotes,
        row_number() over(partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),
UserActivityWindow as (
    select
        u.Id as UserId,
        p.PostTypeId,
        p.CreationDate,
        sum(case when p.CreationDate >= (p.CreationDate - interval '30 days') then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as PostsLast30Days,
        sum(case when p.CreationDate >= (p.CreationDate - interval '365 days') then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as PostsLastYear
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
FilteredQuestionsWithBadges as (
    select
        qs.QuestionId,
        qs.Title,
        qs.QuestionOwnerId,
        u.DisplayName as QuestionOwnerName,
        qs.QuestionScore,
        qs.QuestionViews,
        qs.Tags,
        count(distinct b.Id) as DistinctBadgesCount,
        max(b.Class) filter (where b.Class is not null) as MaxBadgeClass,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as ClosedDate,
        count(distinct c.Id) as CommentCount,
        count(distinct al.AnswerId) as TotalAnswersWithDownvotes
    from QuestionAnswerStats qs
    inner join Users u on u.Id = qs.QuestionOwnerId
    left join Badges b on b.UserId = qs.QuestionOwnerId
    left join PostHistory ph on ph.PostId = qs.QuestionId and ph.PostHistoryTypeId = 10
    left join Comments c on c.PostId = qs.QuestionId
    left join (select * from QuestionAnswerStats where AnswerHasDownvotes = true) al on al.QuestionId = qs.QuestionId
    where qs.AnswerRank <= 5
    group by
        qs.QuestionId,
        qs.Title,
        qs.QuestionOwnerId,
        u.DisplayName,
        qs.QuestionScore,
        qs.QuestionViews,
        qs.Tags
),
ComplicatedBadLogic as (
    select
        fqw.*,
        case 
            when MaxBadgeClass = 1 then 'Gold'
            when MaxBadgeClass = 2 then 'Silver'
            when MaxBadgeClass = 3 then 'Bronze'
            else 'None'
        end as MaxBadgeLevel,
        case
            when ClosedDate is not null then 'Closed'
            else 'Open'
        end as PostStatus,
        length(Tags) - length(replace(Tags, '<', '')) as TagCount,
        regexp_replace(lower(Title), '[^a-z0-9 ]', '', 'g') as CleanTitle,
        substring(regexp_replace(lower(Title), '[^a-z0-9 ]', '', 'g') from 1 for 20) as TitleSnippet,
        ( (QuestionScore * 3) + (QuestionViews / 10.0) ) / greatest(length(Tags) - length(replace(Tags, '<', '')), 1) as WeightedScore,
        cast(round(random() * 1000) as int) as RandomScoreFactor
    from FilteredQuestionsWithBadges fqw
),
TopCandidates as (
    select *,
        row_number() over (partition by PostStatus order by WeightedScore desc, DistinctBadgesCount desc) as RankByStatus
    from ComplicatedBadLogic
)
select
    tc.QuestionId,
    tc.Title,
    tc.QuestionOwnerName,
    tc.DistinctBadgesCount,
    tc.MaxBadgeLevel,
    tc.PostStatus,
    tc.TagCount,
    tc.TitleSnippet,
    tc.WeightedScore,
    tc.RandomScoreFactor,
    dup.PostId as DuplicateOfQuestionId,
    dup.RelatedPostId as DuplicateTargetId,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateTargetTitle
from TopCandidates tc
left join DuplicateLinks dup on dup.PostId = tc.QuestionId
where tc.RankByStatus <= 10
order by tc.PostStatus, tc.WeightedScore desc, tc.DistinctBadgesCount desc;