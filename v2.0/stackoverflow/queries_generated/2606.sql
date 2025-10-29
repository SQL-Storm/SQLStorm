-- {"query": "2606.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1447} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
TopUsers as (
    select UserId, DisplayName, BadgeName, BadgeClass
    from RecursiveUserBadges
    where rn <= 3
),
PostScores as (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        case 
            when p.PostTypeId = 1 then coalesce(p.AnswerCount,0) 
            else 0 
        end as AnswerCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    where p.CreationDate >= current_date - interval '1 year'
),
UserActivity as (
    select 
        u.Id as UserId,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        max(p.CreationDate) as LastPostDate,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        string_agg(distinct t.TagName, ', ') as PopularTags
    from Users u
    left join Posts p on u.Id = p.OwnerUserId and p.CreationDate >= current_date - interval '1 year'
    left join Comments c on u.Id = c.UserId and c.CreationDate >= current_date - interval '1 year'
    left join Votes v on p.Id = v.PostId
    left join LATERAL (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
        from Posts p2
        where p2.OwnerUserId = u.Id and p2.CreationDate >= current_date - interval '1 year' and p2.Tags is not null
        limit 10
    ) t on true
    group by u.Id
),
CloseReopenStats as (
    select 
        p.OwnerUserId,
        sum(case when pht.PostHistoryTypeId = 10 then 1 else 0 end) as TimesClosed,
        sum(case when pht.PostHistoryTypeId = 11 then 1 else 0 end) as TimesReopened,
        count(distinct p.Id) as PostsWithCloseEvents
    from Posts p
    join PostHistory pht on p.Id = pht.PostId and pht.PostHistoryTypeId in (10,11)
    group by p.OwnerUserId
),
RankedPostsWithDupes as (
    select distinct
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        pl.LinkTypeId,
        pl.RelatedPostId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as OwnerPostRank
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3 -- duplicates only
    where p.PostTypeId = 1 and p.CreationDate > current_date - interval '2 years'
),
UserScoreStats as (
    select 
        ua.UserId,
        ua.TotalPosts,
        ua.TotalComments,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        ua.PopularTags,
        coalesce(cr.TimesClosed, 0) as TimesClosed,
        coalesce(cr.TimesReopened, 0) as TimesReopened,
        coalesce(cr.PostsWithCloseEvents, 0) as PostsWithCloseEvents
    from UserActivity ua
    left join CloseReopenStats cr on ua.UserId = cr.OwnerUserId
    where ua.TotalPosts > 10
),
BadgeCounts as (
    select 
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
),
UserRankedByReputation as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    where u.Reputation is not null
),
FinalUserStats as (
    select 
        us.UserId,
        us.TotalPosts,
        us.TotalComments,
        us.UpVotesReceived,
        us.DownVotesReceived,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        us.TimesClosed,
        us.TimesReopened,
        ur.Reputation,
        ur.ReputationRank,
        us.PopularTags
    from UserScoreStats us
    left join BadgeCounts bc on us.UserId = bc.UserId
    join UserRankedByReputation ur on us.UserId = ur.Id
)
select 
    fus.UserId,
    fus.ReputationRank,
    fus.Reputation,
    fus.TotalPosts,
    fus.TotalComments,
    fus.UpVotesReceived,
    fus.DownVotesReceived,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.TimesClosed,
    fus.TimesReopened,
    fus.PopularTags,
    coalesce(tp.PostRank, 0) as TopPostRank,
    tp.Title as TopPostTitle,
    tp.Score as TopPostScore,
    tp.ViewCount as TopPostViews,
    case 
        when fus.TimesClosed > fus.TimesReopened then 'Often Closed' 
        when fus.TimesClosed = 0 then 'Never Closed'
        else 'Occasionally Closed' 
    end as CloseStatus,
    case 
        when fus.GoldBadges > 5 then 'Elite'
        when fus.GoldBadges between 1 and 5 then 'Experienced'
        else 'Novice'
    end as BadgeLevel
from FinalUserStats fus
left join PostScores tp on fus.UserId = tp.OwnerUserId and tp.PostRank = 1
where fus.ReputationRank <= 100
order by fus.ReputationRank asc, tp.Score desc
limit 50;