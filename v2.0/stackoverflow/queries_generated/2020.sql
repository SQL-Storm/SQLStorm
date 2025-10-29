-- {"query": "2020.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1650} 
with RecursivePostHierarchy as (
    select 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        0 as Level,
        array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 -- Questions only
    union all
    select
        c.Id,
        c.PostTypeId,
        c.ParentId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.OwnerUserId,
        c.Title,
        r.Level + 1,
        r.Path || c.Id
    from Posts c
    join RecursivePostHierarchy r on c.ParentId = r.Id
    where c.PostTypeId = 2 -- Answers only
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        coalesce(sum(pb.Score),0) as TotalPostScore,
        max(u.Reputation) as Reputation,
        max(u.CreationDate) as UserCreationDate
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts pb on pb.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
PostsWithCloseHistory as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as LastClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as LastReopenedDate,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseCount
    from PostHistory ph
    group by ph.PostId
),
RanksCTE as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerRep,
        pwc.LastClosedDate,
        pwc.LastReopenedDate,
        pwc.CloseCount,
        row_number() over (
            partition by u.Id 
            order by p.Score desc, p.ViewCount desc 
        ) as UserPostRank,
        dense_rank() over (
            order by p.Tags
        ) as TagRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join PostsWithCloseHistory pwc on pwc.PostId = p.Id
    where p.PostTypeId = 1 -- questions only
),
FilteredQuestions as (
    select 
        r.Id,
        r.Title,
        r.CreationDate,
        r.Score,
        r.ViewCount,
        r.OwnerName,
        r.OwnerRep,
        r.LastClosedDate,
        r.LastReopenedDate,
        r.CloseCount,
        array_length(string_to_array(coalesce(r.Tags, ''), '><'),1) as NumTags,
        r.UserPostRank,
        r.TagRank
    from RanksCTE r
    where r.Score > 10
      and r.CloseCount < 3
      and r.ViewCount > 100
      and r.UserPostRank <= 5
),
UserCommentActivity as (
    select
        c.UserId,
        u.DisplayName,
        count(distinct c.Id) as TotalComments,
        count(distinct c.PostId) as UniquePostsCommented,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    left join Users u on c.UserId = u.Id
    where c.UserId is not null
    group by c.UserId, u.DisplayName
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalPostScore,
        ua.TotalComments,
        ua.UniquePostsCommented,
        ua.LastCommentDate,
        u.Reputation,
        u.CreationDate
    from Users u
    left join UserBadgeStats ub on ub.UserId = u.Id
    left join UserCommentActivity ua on ua.UserId = u.Id
),
DuplicatesCTE as (
    select distinct p.Id as QuestionId, pl.RelatedPostId as DuplicateOfId
    from PostLinks pl
    join Posts p on p.Id = pl.PostId
    where pl.LinkTypeId = 3 -- duplicate
),
CombinedQuestions as (
    select 
        fq.Id,
        fq.Title,
        fq.CreationDate,
        fq.Score,
        fq.ViewCount,
        fq.OwnerName,
        fq.OwnerRep,
        fq.LastClosedDate,
        fq.LastReopenedDate,
        fq.CloseCount,
        fq.NumTags,
        fq.UserPostRank,
        fq.TagRank,
        d.DuplicateOfId
    from FilteredQuestions fq
    left join DuplicatesCTE d on d.QuestionId = fq.Id
)
select 
    cq.Id as QuestionId,
    cq.Title,
    concat(
        '[Tags: ', coalesce(
            substring(cq.Title from '\[(.*?)\]'), 'NoTags'
        ), ']'
    ) as ExtractedTagNames,
    cq.CreationDate,
    date_part('year', age(current_date, cq.CreationDate)) as AgeYears,
    cq.Score,
    cq.ViewCount,
    cq.OwnerName,
    cq.OwnerRep,
    cq.LastClosedDate,
    cq.LastReopenedDate,
    cq.CloseCount,
    cq.NumTags,
    cq.UserPostRank,
    cq.TagRank,
    coalesce(cq.DuplicateOfId, -1) as DuplicateOfId,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalPostScore,
    ua.TotalComments,
    ua.UniquePostsCommented,
    ua.LastCommentDate,
    ua.Reputation as UserReputation,
    ua.CreationDate as UserCreationDate,
    row_number() over (
        order by cq.Score desc, cq.ViewCount desc
    ) as OverallRank,
    case 
        when cq.CloseCount > 0 then 'Closed'
        when cq.DuplicateOfId is not null then 'Duplicate'
        else 'Open' 
    end as PostStatus,
    case 
        when ua.TotalComments > 100 then 'Highly Active Commenter'
        when ua.TotalComments between 10 and 100 then 'Moderately Active Commenter'
        else 'Low Comment Activity' 
    end as CommentActivityCategory,
    upper(trim(coalesce(u.Location, 'Unknown'))) as UserLocation,
    coalesce(
        (select string_agg(b.Name, ', ' order by b.Date desc limit 3)
         from Badges b where b.UserId = cq.OwnerUserId),
        'No Recent Badges'
    ) as RecentBadges,
    (
        select count(*) 
        from PostHistory ph 
        where ph.PostId = cq.Id and ph.PostHistoryTypeId in (4,5,6)
          and ph.UserId is not null
          and ph.CreationDate > cq.CreationDate + interval '30 days'
    ) as PostEditsAfterFirstMonth
from CombinedQuestions cq
left join UserActivitySummary ua on ua.Id = (
    select u.Id from Users u where u.DisplayName = cq.OwnerName limit 1
)
left join Users u on u.DisplayName = cq.OwnerName
order by OverallRank
limit 100;