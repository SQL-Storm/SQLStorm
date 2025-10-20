with RecursiveUserBadges as (
    select 
        u.Id as UserId, 
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as TotalQuestions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as TotalAnswers,
        avg(p.Score) as AveragePostScore,
        max(p.Score) as MaxPostScore,
        sum(p.ViewCount) as TotalViews
    from Posts p
    where p.OwnerUserId > 0
    group by p.OwnerUserId
),
UserRecentActivity as (
    select
        u.Id as UserId,
        max(p.LastActivityDate) as LastPostActivity,
        (select max(c.CreationDate) 
         from Comments c 
         where c.UserId = u.Id
        ) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
TopTagsByUser as (
    select
        p.OwnerUserId as UserId,
        tag as Tag,
        count(*) as TagCount,
        row_number() over (partition by p.OwnerUserId order by count(*) desc) as TagRank
    from Posts p,
    lateral (
      select trim(BOTH ' ' from regexp_split_to_table(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag
    ) t
    where p.PostTypeId = 1 and p.Tags is not null
    group by p.OwnerUserId, tag
),
CloseReasonsAggregate as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVotesCount
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id and ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
PostWithRecentVotes as (
    select
        p.Id as PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        v.VoteTypeId,
        v.CreationDate as VoteDate,
        row_number() over (partition by p.Id order by v.CreationDate desc) as VoteRankDesc
    from Posts p
    left join Votes v on p.Id = v.PostId
    where p.PostTypeId in (1, 2)
),
RankedVotes as (
    select 
        PostId, VoteTypeId, VoteDate
    from PostWithRecentVotes
    where VoteRankDesc <= 3
),
UserVoteAggregates as (
    select
        u.Id as UserId,
        count(case when v.VoteTypeId = 2 then 1 end) as TotalUpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) as TotalDownVotes,
        count(case when v.VoteTypeId = 5 then 1 end) as TotalFavorites,
        count(case when v.VoteTypeId in (8,9) then 1 end) as TotalBounties
    from Users u
    left join Votes v on v.UserId = u.Id
    group by u.Id
)
select 
    u.Id as UserId,
    u.DisplayName,
    us.TotalPosts,
    us.TotalQuestions,
    us.TotalAnswers,
    us.AveragePostScore,
    us.MaxPostScore,
    us.TotalViews,
    ur.LastPostActivity,
    ur.LastCommentDate,
    coalesce(tb.Tag, 'NoTag') as FavoriteTag,
    rub.BadgeName,
    rub.BadgeClass,
    cra.CloseReasonName,
    cra.CloseVotesCount,
    uva.TotalUpVotes,
    uva.TotalDownVotes,
    uva.TotalFavorites,
    uva.TotalBounties,
    case 
        when us.TotalPosts > 0 then CAST(us.TotalViews AS double precision) / us.TotalPosts 
        else 0 
    end as AverageViewsPerPost,
    length(u.AboutMe) as AboutMeLength,
    (select count(1) 
     from Posts p2 
     where p2.OwnerUserId = u.Id and p2.Score >= 
        (select avg(p3.Score) from Posts p3 where p3.OwnerUserId = u.Id)
    ) as PostsAboveUserAverageScore
from Users u
left join UserPostStats us on us.UserId = u.Id
left join UserRecentActivity ur on ur.UserId = u.Id
left join TopTagsByUser tb on tb.UserId = u.Id and tb.TagRank = 1
left join RecursiveUserBadges rub on rub.UserId = u.Id and rub.BadgeRank = 1
left join CloseReasonsAggregate cra on cra.PostId = (select min(p.Id) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1)
left join UserVoteAggregates uva on uva.UserId = u.Id
where u.CreationDate < CAST('2024-10-01 12:34:56' AS timestamp) - interval '1 year'
group by
    u.Id,
    u.DisplayName,
    us.TotalPosts,
    us.TotalQuestions,
    us.TotalAnswers,
    us.AveragePostScore,
    us.MaxPostScore,
    us.TotalViews,
    ur.LastPostActivity,
    ur.LastCommentDate,
    tb.Tag,
    rub.BadgeName,
    rub.BadgeClass,
    cra.CloseReasonName,
    cra.CloseVotesCount,
    uva.TotalUpVotes,
    uva.TotalDownVotes,
    uva.TotalFavorites,
    uva.TotalBounties,
    u.AboutMe
order by us.TotalAnswers desc NULLS LAST, us.AveragePostScore desc NULLS LAST
limit 50;