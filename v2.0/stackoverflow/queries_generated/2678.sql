-- {"query": "2678.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1988} 
with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by coalesce(u.Reputation,0) desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScores as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        coalesce(p.ViewCount,0) as ViewCount,
        -- length of the body excluding HTML tags (simple length ignoring tags for demo)
        length(regexp_replace(p.Body, '<[^>]*>', '', 'g')) as BodyTextLength,
        p.Tags,
        -- Extract first tag from Tags string formatted as <tag1><tag2><tag3>
        substring(p.Tags from '<([^>]+)>') as FirstTag
    from Posts p
    where p.PostTypeId in (1, 2)
),
UserPostRanks as (
    select
        ps.OwnerUserId,
        ps.Id as PostId,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.BodyTextLength,
        ps.CreationDate,
        ps.FirstTag,
        rank() over (partition by ps.OwnerUserId order by ps.Score desc, ps.ViewCount desc nulls last) as ScoreRank,
        row_number() over (partition by ps.OwnerUserId order by ps.CreationDate) as PostAgeRank
    from PostScores ps
    where ps.OwnerUserId is not null
),
TopPostsWithComments as (
    select
        upr.OwnerUserId,
        upr.PostId,
        upr.PostTypeId,
        upr.Score,
        upr.ViewCount,
        upr.BodyTextLength,
        upr.CreationDate,
        upr.FirstTag,
        c.CommentCount,
        c.TotalCommentScore,
        bp.BountyCount
    from UserPostRanks upr
    left join lateral (
        select
            count(*) as CommentCount,
            coalesce(sum(cmt.Score),0) as TotalCommentScore
        from Comments cmt
        where cmt.PostId = upr.PostId
    ) c on true
    left join lateral (
        select count(*) as BountyCount
        from Votes v
        where v.PostId = upr.PostId and v.VoteTypeId = 8 -- BountyStart
    ) bp on true
    where upr.ScoreRank <= 5
),
DuplicateQuestionLinks as (
    select
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3 -- Duplicate
),
RecentPostHistoryChanges as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        count(*) as ChangeCount,
        min(ph.CreationDate) as FirstChangeDate,
        max(ph.CreationDate) as LastChangeDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    where ph.CreationDate > now() - interval '90 days'
    group by ph.PostId, ph.PostHistoryTypeId, pht.Name
),
AggregatedUserStats as (
    select
        ub.UserId,
        ub.DisplayName,
        coalesce(sum(tpc.Score),0) as TotalScoreOnTopPosts,
        coalesce(sum(tpc.ViewCount),0) as TotalViewsOnTopPosts,
        coalesce(avg(tpc.BodyTextLength),0) as AvgBodyLengthOnTopPosts,
        coalesce(sum(tpc.CommentCount),0) as TotalCommentsOnTopPosts,
        coalesce(sum(tpc.BountyCount),0) as TotalBountiesOnTopPosts,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        -- Days since last access
        extract(epoch from (now() - u.LastAccessDate))/86400 as DaysSinceLastAccess,
        -- Has website url
        case when u.WebsiteUrl is not null and length(trim(u.WebsiteUrl)) > 0 then 1 else 0 end as HasWebsite,
        -- Location contains 'USA' or 'United States' (case insensitive)
        case when lower(coalesce(u.Location,'')) like '%usa%' or lower(coalesce(u.Location,'')) like '%united states%' then 1 else 0 end as IsFromUSA
    from UserBadgeCounts ub
    join Users u on u.Id = ub.UserId
    left join TopPostsWithComments tpc on tpc.OwnerUserId = ub.UserId
    group by ub.UserId, ub.DisplayName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, u.Reputation, u.CreationDate, u.LastAccessDate, u.WebsiteUrl, u.Location
),
FinalRankedUsers as (
    select
        aus.*,
        row_number() over (order by aus.TotalScoreOnTopPosts desc nulls last, aus.Reputation desc nulls last) as OverallRank
    from AggregatedUserStats aus
),
FilteredRecentEdits as (
    select
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        p.Title,
        ph.PostHistoryTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount
    from PostHistory ph
    join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
      and ph.CreationDate > now() - interval '30 days'
),
UserEditsSummary as (
    select
        fre.UserId,
        count(distinct fre.PostId) as DistinctPostsEdited,
        count(*) as TotalEdits,
        min(fre.CreationDate) as FirstEditDate,
        max(fre.CreationDate) as LastEditDate,
        avg(fre.Score) as AvgPostScoreOnEdits,
        avg(fre.ViewCount) as AvgPostViewCountOnEdits
    from FilteredRecentEdits fre
    group by fre.UserId
)
select
    fru.UserId,
    fru.DisplayName,
    fru.Reputation,
    fru.GoldBadges,
    fru.SilverBadges,
    fru.BronzeBadges,
    fru.TotalScoreOnTopPosts,
    fru.TotalViewsOnTopPosts,
    fru.AvgBodyLengthOnTopPosts,
    fru.TotalCommentsOnTopPosts,
    fru.TotalBountiesOnTopPosts,
    fru.DaysSinceLastAccess,
    fru.HasWebsite,
    fru.IsFromUSA,
    coalesce(ues.DistinctPostsEdited,0) as RecentDistinctPostsEdited,
    coalesce(ues.TotalEdits,0) as RecentTotalEdits,
    coalesce(ues.AvgPostScoreOnEdits,0) as RecentAvgPostScoreOnEdits,
    coalesce(ues.AvgPostViewCountOnEdits,0) as RecentAvgPostViewCountOnEdits,
    -- Correlated subquery for count of questions duplicates pointed at user questions
    (
      select count(distinct pl.PostId)
      from Posts p
      join PostLinks pl on pl.RelatedPostId = p.Id and pl.LinkTypeId = 3
      where p.OwnerUserId = fru.UserId and p.PostTypeId = 1
    ) as TotalDuplicateQuestionsLinked,
    -- Correlated subquery to find most recent duplicate link creation date for user questions
    (
      select max(pl.CreationDate)
      from Posts p
      join PostLinks pl on pl.RelatedPostId = p.Id and pl.LinkTypeId = 3
      where p.OwnerUserId = fru.UserId and p.PostTypeId = 1
    ) as LastDuplicateLinkDate,
    -- Compute activity span of user posts in days (max post creation - min post creation)
    (select
         coalesce(extract(epoch from (max(CreationDate) - min(CreationDate)))/86400, 0)
     from Posts p2
     where p2.OwnerUserId = fru.UserId and p2.PostTypeId in (1,2)
    ) as PostActivitySpanDays
from FinalRankedUsers fru
left join UserEditsSummary ues on ues.UserId = fru.UserId
where fru.TotalScoreOnTopPosts > 100
order by fru.OverallRank
limit 100;