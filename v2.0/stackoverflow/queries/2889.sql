-- {"query": "2889.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1543} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score as PostScore,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        coalesce(p.Tags,'') as Tags,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation >= 1000
), RecentUserPosts as (
    select *
    from RecursiveUserActivity
    where rn <= 5
), UserBadgeCounts as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges
    group by UserId
), PostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount,
        count(distinct pl.RelatedPostId) as TotalLinks,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl 
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
), PostScoreStats as (
    select
        p.Id as PostId,
        p.OwnerUserId as UserId,
        p.PostTypeId,
        avg(coalesce(vt.UpVotes, 0)) as AvgUpVotes,
        avg(coalesce(vt.DownVotes, 0)) as AvgDownVotes,
        count(v.Id) as VoteCount,
        sum(case when vt.UpVotes is not null then vt.UpVotes else 0 end) as TotalUpVotes,
        sum(case when vt.DownVotes is not null then vt.DownVotes else 0 end) as TotalDownVotes
    from Posts p
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) vt on vt.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.OwnerUserId, p.PostTypeId
), UserActivitySummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        coalesce(ps.AvgUpVotes,0) as AvgUpVotes,
        coalesce(ps.AvgDownVotes,0) as AvgDownVotes,
        coalesce(ps.VoteCount,0) as TotalVotes,
        pld.DuplicateCount,
        pld.TotalLinks,
        pld.LastLinkDate,
        ru.PostId,
        ru.PostTypeId,
        ru.PostScore,
        ru.ViewCount,
        ru.PostCreationDate,
        ru.Tags,
        ru.HasAcceptedAnswer,
        dense_rank() over (partition by u.Id order by ru.PostScore desc) as PostRankByScore,
        dense_rank() over (partition by u.Id order by ru.ViewCount desc) as PostRankByViews
    from Users u
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join PostScoreStats ps on ps.UserId = u.Id
    left join PostLinkDuplicates pld on pld.PostId = ps.PostId
    left join RecentUserPosts ru on ru.UserId = u.Id
    where u.DisplayName is not null
), FilteredUserActivity as (
    select *
    from UserActivitySummary
    where PostRankByScore <= 3
), ComplexCorrelatedData as (
    select 
        fua.UserId,
        fua.DisplayName,
        fua.Reputation,
        fua.GoldBadges,
        fua.SilverBadges,
        fua.BronzeBadges,
        fua.TotalBadges,
        fua.PostId,
        fua.PostScore,
        fua.ViewCount,
        fua.Tags,
        fua.HasAcceptedAnswer,
        fua.TotalLinks,
        fua.DuplicateCount,
        fua.LastLinkDate,
        -- Correlated subquery calculating count of comments on the post excluding deleted users
        (select count(1) from Comments c where c.PostId = fua.PostId and c.UserId is not null and c.UserId <> fua.UserId) as OtherUserCommentCount,
        -- Window function calculating running total of post scores per user ordered by post creation date
        sum(fua.PostScore) over (partition by fua.UserId order by fua.PostCreationDate rows between unbounded preceding and current row) as RunningScoreTotal,
        -- String expression: concatenation and trimming tags
        trim(both '<>' from fua.Tags) as CleanTags,
        -- Complex NULL and CASE expression for premium user status
        case 
            when fua.Reputation > 10000 and fua.GoldBadges > 0 and fua.TotalLinks > 5 then 'Premium'
            when fua.Reputation between 1000 and 10000 then 'Intermediate'
            else 'Beginner'
        end as UserLevel,
        -- Condition checking if post is accepted and highly viewed
        case when fua.HasAcceptedAnswer = 1 and fua.ViewCount > 10000 then 'HighImpactAccepted' else 'Normal' end as ImpactStatus
    from FilteredUserActivity fua
)
select
    ccd.UserId,
    ccd.DisplayName,
    ccd.UserLevel,
    ccd.Reputation,
    ccd.GoldBadges,
    ccd.SilverBadges,
    ccd.BronzeBadges,
    ccd.TotalBadges,
    ccd.PostId,
    ccd.PostScore,
    ccd.RunningScoreTotal,
    ccd.ViewCount,
    ccd.CleanTags,
    ccd.OtherUserCommentCount,
    ccd.TotalLinks,
    ccd.DuplicateCount,
    ccd.LastLinkDate,
    ccd.ImpactStatus
from ComplexCorrelatedData ccd
where
    -- Filtering posts with at least 1 gold badge user and more than 2 duplicates linked
    ccd.GoldBadges > 0 and ccd.DuplicateCount > 2
    and (
      -- complex predicate mixing NULL logic and string pattern matching
      (ccd.CleanTags is not null and position('sql' in lower(ccd.CleanTags)) > 0)
      or
      (ccd.OtherUserCommentCount > 5 and ccd.ImpactStatus = 'HighImpactAccepted')
    )
order by ccd.UserLevel desc, ccd.RunningScoreTotal desc, ccd.ViewCount desc;