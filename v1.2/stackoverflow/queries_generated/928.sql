-- {"query": "928.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1790} 
with RecursivePostCounts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as rn,
        count(*) over (partition by p.OwnerUserId) as total_posts
    from Posts p
    where p.PostTypeId in (1,2) -- Questions and Answers
),
UserBadgeStats as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.TagBased) as BadgeTypes
    from Badges b
    group by b.UserId
),
AggregatedVotes as (
    select
        p.OwnerUserId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        count(v.Id) as TotalVotes
    from Posts p
    left join Votes v on p.Id = v.PostId
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
DuplicateLinks as (
    select distinct
        pl.PostId,
        pl.RelatedPostId,
        u.DisplayName as OwnerDisplayName,
        p.Title as PostTitle,
        rp.Title as RelatedPostTitle
    from PostLinks pl
    inner join Posts p on pl.PostId = p.Id
    inner join Posts rp on pl.RelatedPostId = rp.Id
    left join Users u on p.OwnerUserId = u.Id
    where pl.LinkTypeId = 3
),
CloseReasonsCount as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseVotes
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
),
TopPostsWithCloseAndVotes as (
    select
        rpc.Id as PostId,
        rpc.PostTypeId,
        rpc.Title,
        rpc.Score,
        rpc.ViewCount,
        rpc.AnswerCount,
        ar.CloseReason,
        coalesce(av.UpVotes,0) as UpVotes,
        coalesce(av.DownVotes,0) as DownVotes,
        coalesce(av.Favorites,0) as Favorites,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.CreationDate as UserCreationDate,
        u.LastAccessDate,
        case when u.WebsiteUrl is null or length(trim(u.WebsiteUrl)) = 0 then 'No Website' else u.WebsiteUrl end as WebsiteUrl,
        substr(coalesce(rpc.Tags,''), 2, length(coalesce(rpc.Tags,'')) - 2) as CleanedTags,
        row_number() over (partition by rpc.OwnerUserId order by rpc.Score desc, rpc.ViewCount desc) as rn
    from RecursivePostCounts rpc
    left join CloseReasonsCount ar on rpc.Id = ar.PostId
    left join AggregatedVotes av on av.PostId = rpc.Id
    left join UserBadgeStats ubs on ubs.UserId = rpc.OwnerUserId
    left join Users u on u.Id = rpc.OwnerUserId
    where rpc.rn = 1
),
UserActivityWindow as (
    select
        p.OwnerUserId,
        count(*) as PostsCount,
        sum(p.Score) as TotalScore,
        min(p.CreationDate) as FirstPostDate,
        max(p.CreationDate) as LastPostDate,
        max(p.CreationDate) - min(p.CreationDate) as ActivitySpanDays,
        avg(p.Score) as AvgPostScore,
        count(distinct p.PostTypeId) as PostTypeVariety
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserCommentActivity as (
    select
        c.UserId,
        count(c.Id) as TotalComments,
        max(c.CreationDate) as LastCommentDate,
        count(distinct c.PostId) as DistinctPostsCommented,
        sum(c.Score) as TotalCommentScore
    from Comments c
    group by c.UserId
),
UserCombinedActivity as (
    select
        ua.OwnerUserId as UserId,
        ua.PostsCount,
        ua.TotalScore,
        ua.FirstPostDate,
        ua.LastPostDate,
        ua.ActivitySpanDays,
        ua.AvgPostScore,
        ua.PostTypeVariety,
        coalesce(uca.TotalComments,0) as TotalComments,
        coalesce(uca.DistinctPostsCommented,0) as DistinctPostsCommented,
        coalesce(uca.TotalCommentScore,0) as TotalCommentScore
    from UserActivityWindow ua
    left join UserCommentActivity uca on ua.OwnerUserId = uca.UserId
),
FinalResult as (
    select distinct
        t.PostId,
        t.Title,
        t.Score,
        t.ViewCount,
        t.AnswerCount,
        coalesce(t.CloseReason, 'Open') as CloseReason,
        t.UpVotes,
        t.DownVotes,
        t.Favorites,
        t.GoldBadges,
        t.SilverBadges,
        t.BronzeBadges,
        t.DisplayName,
        t.Reputation,
        t.Location,
        t.UserCreationDate,
        t.LastAccessDate,
        t.WebsiteUrl,
        t.CleanedTags,
        uca.PostsCount,
        uca.TotalScore as UserTotalScore,
        uca.FirstPostDate as UserFirstPostDate,
        uca.LastPostDate as UserLastPostDate,
        uca.ActivitySpanDays,
        uca.AvgPostScore,
        uca.PostTypeVariety,
        uca.TotalComments,
        uca.DistinctPostsCommented,
        uca.TotalCommentScore
    from TopPostsWithCloseAndVotes t
    left join UserCombinedActivity uca on t.OwnerUserId = uca.UserId
    where t.Score > 5
    order by t.Score desc nulls last, t.ViewCount desc nulls last
    limit 100
)
select
    fr.PostId,
    fr.Title,
    fr.Score,
    fr.ViewCount,
    fr.AnswerCount,
    fr.CloseReason,
    fr.UpVotes,
    fr.DownVotes,
    fr.Favorites,
    concat_ws(' / ',
        'Gold:', fr.GoldBadges,
        'Silver:', fr.SilverBadges,
        'Bronze:', fr.BronzeBadges) as BadgeSummary,
    coalesce(fr.DisplayName, 'Unknown User') as UserDisplayName,
    fr.Reputation,
    coalesce(fr.Location, 'Unknown Location') as UserLocation,
    to_char(fr.UserCreationDate, 'YYYY-MM-DD') as UserJoined,
    to_char(fr.LastAccessDate, 'YYYY-MM-DD') as LastSeen,
    fr.WebsiteUrl,
    fr.CleanedTags,
    fr.PostsCount,
    fr.UserTotalScore,
    to_char(fr.UserFirstPostDate, 'YYYY-MM-DD') as UserFirstPost,
    to_char(fr.UserLastPostDate, 'YYYY-MM-DD') as UserLastPost,
    coalesce(fr.ActivitySpanDays, interval '0 day') as ActivityDuration,
    round(fr.AvgPostScore::numeric, 2) as AveragePostScore,
    fr.PostTypeVariety,
    fr.TotalComments,
    fr.DistinctPostsCommented,
    fr.TotalCommentScore
from FinalResult fr;