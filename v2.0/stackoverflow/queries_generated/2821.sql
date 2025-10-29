-- {"query": "2821.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1449} 
with RecursivePostTree as (
    select 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        1 as Level,
        p.AcceptedAnswerId
    from Posts p
    where p.PostTypeId = 1 -- questions only, roots

    union all

    select 
        c.Id,
        c.PostTypeId,
        c.ParentId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.Title,
        c.Tags,
        c.OwnerUserId,
        rpt.Level + 1,
        c.AcceptedAnswerId
    from Posts c
    inner join RecursivePostTree rpt on c.ParentId = rpt.Id and c.PostTypeId = 2 -- answers linked to questions or answers (if any)
),
BadgeCounts as (
    select 
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadgeCount,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadgeCount,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadgeCount,
        count(*) as TotalBadges
    from Badges
    group by UserId
),
UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(bc.GoldBadgeCount, 0) as GoldBadges,
        coalesce(bc.SilverBadgeCount, 0) as SilverBadges,
        coalesce(bc.BronzeBadgeCount, 0) as BronzeBadges,
        coalesce(bc.TotalBadges, 0) as TotalBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as HighestPostScore,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join BadgeCounts bc on bc.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes, bc.GoldBadgeCount, bc.SilverBadgeCount, bc.BronzeBadgeCount, bc.TotalBadges
),
PostLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        rpost.Score as RelatedPostScore,
        rpost.ViewCount as RelatedPostViewCount
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts rpost on rpost.Id = pl.RelatedPostId
),
PostCloseReasonAggregated as (
    select 
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVoteCount
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
),
RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.OwnerUserId,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last, p.ViewCount desc nulls last) as RowNumByType
    from Posts p
    where p.PostTypeId in (1,2)
)
select distinct
    up.DisplayName,
    up.Reputation,
    up.Location,
    up.TotalBadges,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    up.QuestionsPosted,
    up.AnswersPosted,
    up.HighestPostScore,
    up.AvgPostScore,
    rp.Id as PostId,
    coalesce(rp.Title, '(no title)') as PostTitle,
    rp.PostTypeId,
    rp.CreationDate as PostCreated,
    rp.Score as PostScore,
    rp.ViewCount as PostViews,
    rp.AnswerCount,
    rp.FavoriteCount,
    string_agg(distinct pl.LinkTypeName || '->' || coalesce(lp.RelatedPostId::text, 'NULL') || '(' || coalesce(lp.RelatedPostScore::text,'0') || ')' , '; ') 
        over (partition by rp.Id) as PostLinksSummary,
    (select count(*) from Comments c where c.PostId = rp.Id) as CommentsCount,
    pcr.CloseVoteCount,
    pcr.CloseReasonName,
    -- window function: ranking of this post score within all posts
    rank() over (order by rp.Score desc nulls last) as OverallPostScoreRank,

    -- complex calculation with NULL logic and string manipulation
    case 
        when rp.Tags is null or length(rp.Tags) < 5 then 'NoTags'
        else substring(rp.Tags from 2 for length(rp.Tags)-2)
    end as ParsedTags,

    -- correlated subquery: count of answers for this post (if question)
    (select count(*) from Posts ans where ans.ParentId = rp.Id and ans.PostTypeId = 2) as ActualAnswersCount,

    -- correlated subquery with EXISTS and NULL-safe logic: has accepted answer that exists and is not deleted
    exists (
        select 1 
        from Posts aa 
        where aa.Id = rp.AcceptedAnswerId 
        and aa.PostTypeId = 2
        and aa.DeletionDate is null
    ) as HasValidAcceptedAnswer,

    up.Views * 1.0 / nullif(nullif(rp.ViewCount,0),1) as UserViewsOverPostViewsRatio

from RankedPosts rp
left join UserPostStats up on up.UserId = rp.OwnerUserId
left join PostLinkDetails pl on pl.PostId = rp.Id
left join PostLinkDetails lp on lp.PostId = rp.Id
left join PostCloseReasonAggregated pcr on pcr.PostId = rp.Id
where rp.RowNumByType <= 100
order by up.TotalBadges desc nulls last, rp.Score desc nulls last, rp.ViewCount desc nulls last
limit 200;