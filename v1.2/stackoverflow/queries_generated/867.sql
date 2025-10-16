-- {"query": "867.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1622} 
with RecursiveUserStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        sum(coalesce(p.ViewCount,0)) as TotalPostViews,
        max(p.LastActivityDate) as LastPostActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
), BadgeRanks as (
    select 
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
), UserActivityRanks as (
    select 
        rus.UserId,
        rus.DisplayName,
        rus.Reputation,
        rus.CreationDate,
        rus.QuestionCount,
        rus.AnswerCount,
        rus.TotalPostScore,
        rus.TotalPostViews,
        rus.LastPostActivity,
        coalesce(br.GoldBadges,0) as GoldBadges,
        coalesce(br.SilverBadges,0) as SilverBadges,
        coalesce(br.BronzeBadges,0) as BronzeBadges,
        row_number() over (order by rus.Reputation desc, rus.TotalPostScore desc) as ReputationRank,
        rank() over (order by rus.TotalPostViews desc) as ViewsRank,
        dense_rank() over (order by coalesce(br.GoldBadges,0) desc, coalesce(br.SilverBadges,0) desc) as BadgeRank
    from RecursiveUserStats rus
    left join BadgeRanks br on br.UserId = rus.UserId
), TopPostsPerUser as (
    select distinct on (p.OwnerUserId)
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount
    from Posts p
    where p.OwnerUserId is not null
    order by p.OwnerUserId, p.Score desc, p.ViewCount desc, p.CreationDate desc
), PostCommentsAgg as (
    select 
        c.PostId,
        count(*) as CommentCount,
        sum(coalesce(c.Score,0)) as TotalCommentScore,
        string_agg(distinct coalesce(c.UserDisplayName,'<anonymous>') || ':' || left(c.Text,50), ' | ') as SampleComments
    from Comments c
    group by c.PostId
), PostLinkSummary as (
    select 
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
), ComplexJoinedData as (
    select
        uar.UserId,
        uar.DisplayName,
        uar.Reputation,
        uar.GoldBadges,
        uar.SilverBadges,
        uar.BronzeBadges,
        tpp.PostId,
        tpp.Title,
        tpp.Tags,
        tpp.Score as PostScore,
        tpp.ViewCount,
        tpp.AnswerCount,
        tpp.FavoriteCount,
        pca.CommentCount,
        pca.TotalCommentScore,
        pca.SampleComments,
        pls.LinkedCount,
        pls.DuplicateCount,
        -- correlated subquery for the last edit date of this post
        (select ph.CreationDate 
         from PostHistory ph 
         where ph.PostId = tpp.PostId 
         and ph.PostHistoryTypeId in (4,5,6) -- edit title/body/tags
         order by ph.CreationDate desc 
         limit 1) as LastEditDate,
        -- complex calculation example: weighted score
        ((tpp.Score * 0.7) + (coalesce(pca.TotalCommentScore,0) * 0.2) + (coalesce(tpp.FavoriteCount,0) * 5) + (coalesce(pls.LinkedCount,0) * 1.5) - (coalesce(pls.DuplicateCount,0) * 2)) as WeightedPostScore,
        -- string manipulation: extract array of tags from Tags field (assuming format: '<tag1><tag2><tag3>')
        array_remove(string_to_array(substring(tpp.Tags from 2 for char_length(tpp.Tags) - 2), '><'), '') as TagArray,
        -- window function: total posts per user partitioned by tag count
        count(*) over (partition by uar.UserId) as TotalPostsByUser,
        count(distinct unnest(array_remove(string_to_array(substring(tpp.Tags from 2 for char_length(tpp.Tags) - 2), '><'), ''))) over (partition by uar.UserId) as DistinctTagsCount
    from UserActivityRanks uar
    left join TopPostsPerUser tpp on tpp.OwnerUserId = uar.UserId
    left join PostCommentsAgg pca on pca.PostId = tpp.PostId
    left join PostLinkSummary pls on pls.PostId = tpp.PostId
), FilteredPosts as (
    select *
    from ComplexJoinedData
    where 
      WeightedPostScore > 10
      and Reputation > 1000
      and array_length(TagArray,1) between 1 and 5
      and (LastEditDate is null or LastEditDate > CreationDate - interval '1 year')
), UnifiedSet as (
    select UserId, DisplayName, PostId, WeightedPostScore, 'AboveThreshold' as Category from FilteredPosts
    union
    select UserId, DisplayName, null as PostId, 0 as WeightedPostScore, 'NoHighScorePosts' as Category
    from UserActivityRanks
    where UserId not in (select distinct UserId from FilteredPosts)
)
select 
    us.UserId,
    us.DisplayName,
    us.Category,
    max(fp.Title) filter (where fp.PostId is not null) as TopPostTitle,
    max(fp.WeightedPostScore) filter (where fp.PostId is not null) as TopPostWeightedScore,
    sum(fp.WeightedPostScore) filter (where fp.PostId is not null) as TotalWeightedScore,
    count(fp.PostId) filter (where fp.PostId is not null) as CountHighScorePosts,
    max(fp.Reputation) as UserReputation,
    max(fp.GoldBadges) as UserGoldBadges,
    max(fp.SilverBadges) as UserSilverBadges,
    max(fp.BronzeBadges) as UserBronzeBadges,
    max(fp.TotalPostsByUser) as UserTotalPosts,
    max(fp.DistinctTagsCount) as UserDistinctTagsCount
from UnifiedSet us
left join FilteredPosts fp on fp.UserId = us.UserId
group by us.UserId, us.DisplayName, us.Category
order by TotalWeightedScore desc nulls last, UserReputation desc
limit 100;