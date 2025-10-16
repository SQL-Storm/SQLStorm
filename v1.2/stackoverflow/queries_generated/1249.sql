-- {"query": "1249.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1544} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate as PostCreationDate,
        ph.CreationDate as LastEditDate,
        row_number() over (partition by p.Id order by coalesce(ph.CreationDate, p.CreationDate) desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6)
    where u.Reputation > 1000 and p.CreationDate > '2020-01-01'
),
LatestEdits as (
    select
        UserId,
        DisplayName,
        PostId,
        PostTypeId,
        Score,
        ViewCount,
        AnswerCount,
        FavoriteCount,
        PostCreationDate,
        LastEditDate
    from RecursiveUserActivity
    where rn = 1
),
CloseVotesSummary as (
    select 
        ph.PostId, 
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotes,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment::int else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
),
TopTaggedPosts as (
    select 
        p.Id,
        array_agg(distinct split_part(trim(tag), '><', 1)) filter (where tag is not null) as PostTags
    from Posts p cross join lateral  
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) as tag
    where p.PostTypeId = 1 and p.Tags is not null
    group by p.Id
),
UserBadgesRanks as (
    select 
        b.UserId,
        sum(case when b.Class=1 then 3 else 0 end) as GoldBadgePoints,
        sum(case when b.Class=2 then 2 else 0 end) as SilverBadgePoints,
        sum(case when b.Class=3 then 1 else 0 end) as BronzeBadgePoints,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserActivityScore as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(ub.GoldBadgePoints,0)*5 + coalesce(ub.SilverBadgePoints,0)*3 + coalesce(ub.BronzeBadgePoints,0) as BadgeScore,
        count(distinct p.Id) as PostCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(vcnt.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(vcnt.DownVotes), 0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select 
            p.OwnerUserId,
            sum(case when v.VoteTypeId=2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId=3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vcnt on vcnt.OwnerUserId = u.Id
    left join UserBadgesRanks ub on ub.UserId = u.Id
    where u.Reputation > 500
    group by u.Id, u.DisplayName, u.Reputation, ub.GoldBadgePoints, ub.SilverBadgePoints, ub.BronzeBadgePoints
),
HighActivityPosts as (
    select 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate,
        close.CloseVotes,
        close.ReopenVotes,
        close.CloseReasonId,
        LTP.PostTags
    from Posts p
    left join CloseVotesSummary close on close.PostId = p.Id
    left join TopTaggedPosts LTP on LTP.Id = p.Id
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
TagPopularity as (
    select 
        unnest(PostTags) as TagName,
        count(*) as QuestionsCount,
        avg(Score) as AvgScore,
        avg(ViewCount) as AvgViewCount
    from HighActivityPosts
    group by TagName
),
RankedPosts as (
    select
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate,
        p.CloseVotes,
        p.ReopenVotes,
        tagp.AvgScore as TagAvgScore,
        tagp.AvgViewCount as TagAvgViewCount,
        rank() over (partition by p.OwnerUserId order by p.Score desc) as PostRank
    from HighActivityPosts p
    left join TagPopularity tagp on tagp.TagName = any(p.PostTags)
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.BadgeScore,
    ua.PostCount,
    ua.CommentCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    rp.Id as TopPostId,
    rp.Score as TopPostScore,
    rp.ViewCount as TopPostViews,
    rp.AnswerCount as TopPostAnswers,
    rp.FavoriteCount as TopPostFavorites,
    rp.PostRank,
    rp.CloseVotes,
    rp.ReopenVotes,
    rp.TagAvgScore,
    rp.TagAvgViewCount,
    string_agg(distinct lb.Name || ':' || count(*) filter (where b.Name=lb.Name)::text, ', ') as BadgeSummary
from UserActivityScore ua
left join RankedPosts rp on rp.OwnerUserId = ua.UserId and rp.PostRank = 1
left join Badges b on b.UserId = ua.UserId
left join Lateral (
    select Name from Badges group by Name order by Name limit 10
) lb on lb.Name = b.Name
group by ua.UserId, ua.DisplayName, ua.Reputation, ua.BadgeScore, ua.PostCount, ua.CommentCount, ua.TotalUpVotes, ua.TotalDownVotes,
         rp.Id, rp.Score, rp.ViewCount, rp.AnswerCount, rp.FavoriteCount, rp.PostRank, rp.CloseVotes, rp.ReopenVotes, rp.TagAvgScore, rp.TagAvgViewCount
having 
    ua.PostCount > 5 and 
    (ua.TotalUpVotes - ua.TotalDownVotes)::float / nullif(ua.PostCount,0) > 10
order by ua.BadgeScore desc, ua.Reputation desc
limit 50;