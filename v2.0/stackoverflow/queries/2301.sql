-- {"query": "2301.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 998} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (partition by u.Id order by u.LastAccessDate desc) as rn
    from Users u
    where u.Reputation > 1000
), RecentBadges as (
    select 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        b.TagBased,
        dense_rank() over (partition by b.UserId order by b.Date desc) as BadgeRank,
        b.Date as BadgeDate
    from Badges b
    where b.Date > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
), ActivePosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        count(c.Id) as CommentCount,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        row_number() over(partition by p.OwnerUserId order by p.CreationDate desc) as PostRank
    from Posts p
    left join Comments c on c.PostId = p.Id and c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '6 months'
    where p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.AcceptedAnswerId, p.FavoriteCount, p.AnswerCount
), LatestPostHistory as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.Comment,
        ph.Text as HistoryText
    from PostHistory ph
    where ph.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
    order by ph.PostId, ph.CreationDate desc
), LinkSummary as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
), VoteSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
        count(distinct v.UserId) as VoterCount
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.Views,
    count(distinct ab.BadgeName) filter (where ab.BadgeRank <= 3) as Top3BadgesLastYear,
    count(distinct ap.Id) as ActivePostsLast2Years,
    avg(ap.Score) filter (where ap.PostRank <= 5) as AvgScoreTop5RecentPosts,
    max(vs.UpVotes) filter (where vs.UpVotes is not null) as MaxUpVotesOnPost,
    sum(vs.Favorites) as TotalFavoritesOnPosts,
    string_agg(distinct lt.LinkTypeName, ',' order by lt.LinkTypeName) as DistinctLinkTypesOnPosts,
    max(ph.HistoryDate) as LastPostHistoryDate,
    count(distinct ph.PostId) as PostsWithRecentHistory,
    max(coalesce(length(replace(ap.Tags,'<>',' ')),0)) as MaxTagsLength,
    bool_or(ph.Comment is null) as HasAnyHistoryWithNullComment
from RecursiveUserActivity ua
left join RecentBadges ab on ab.UserId = ua.UserId
left join ActivePosts ap on ap.OwnerUserId = ua.UserId
left join LatestPostHistory ph on ph.PostId = ap.Id
left join LinkSummary lt on lt.PostId = ap.Id
left join VoteSummary vs on vs.PostId = ap.Id
where ua.rn = 1
group by ua.UserId, ua.DisplayName, ua.Reputation, ua.Location, ua.Views
having count(distinct ap.Id) > 5
order by AvgScoreTop5RecentPosts desc nulls last, ua.Reputation desc
limit 100;