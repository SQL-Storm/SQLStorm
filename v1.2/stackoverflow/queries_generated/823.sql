-- {"query": "823.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1627} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        case 
            when u.Reputation > 100000 then 'Elite'
            when u.Reputation > 10000 then 'Pro'
            when u.Reputation > 1000 then 'Intermediate'
            else 'Newbie'
        end as UserLevel,
        1 as ActivityDepth,
        p.Id as PostId,
        p.PostTypeId,
        p.Score as PostScore,
        p.ViewCount as PostViews,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 5000

    union all

    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.Location,
        ua.UserLevel,
        ua.ActivityDepth + 1,
        ph.PostId,
        pht.Id as PostTypeId,
        p2.Score,
        p2.ViewCount,
        p2.CreationDate,
        row_number() over (partition by ua.UserId order by p2.CreationDate desc)
    from RecursiveUserActivity ua
    join PostHistory ph on ph.UserId = ua.UserId
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join Posts p2 on p2.Id = ph.PostId
    where ua.ActivityDepth < 2
),
LatestUserPosts as (
    select 
        UserId,
        max(PostCreationDate) as LatestPostDate
    from RecursiveUserActivity
    group by UserId
),
UserBadgeSummary as (
    select 
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as UniqueBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserPostStats as (
    select 
        p.OwnerUserId as UserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews,
        sum(p.FavoriteCount) filter (where p.PostTypeId = 1) as TotalQuestionFavorites,
        sum(p.CommentCount) as TotalComments
    from Posts p
    group by p.OwnerUserId
),
TopTagsByUser as (
    select distinct on (u.Id, t.TagName)
        u.Id as UserId,
        t.TagName,
        t.Count as TagCount,
        p.Score as TagPostMaxScore,
        row_number() over (partition by u.Id order by t.Count desc, p.Score desc nulls last) as TagRank
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    join Tags t on position('<' || t.TagName || '>' in p.Tags) > 0
    where u.Reputation > 5000
),
UserAggregatedTags as (
    select 
        UserId,
        string_agg(TagName || '(' || TagCount || ')', ', ' order by TagCount desc) as TagsSummary
    from TopTagsByUser
    where TagRank <= 5
    group by UserId
),
UserCloseVoteSummary as (
    select
        ph.UserId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCast,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotesCast,
        count(distinct ph.PostId) as DistinctPostsVoted
    from PostHistory ph
    where ph.UserId is not null
    group by ph.UserId
),
UserVotingStats as (
    select 
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast,
        count(distinct v.PostId) as DistinctPostsVotedOn
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.UserLevel,
    u.Location,
    lub.LatestPostDate,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    coalesce(ubs.UniqueBadges, 0) as UniqueBadges,
    upst.QuestionCount,
    upst.AnswerCount,
    round(coalesce(upst.AvgPostScore,0),2) as AvgPostScore,
    coalesce(upst.TotalQuestionViews,0) as TotalQuestionViews,
    coalesce(upst.TotalQuestionFavorites,0) as TotalQuestionFavorites,
    coalesce(upst.TotalComments,0) as TotalComments,
    coalesce(ut.TagsSummary, '') as TopTags,
    coalesce(ucs.CloseVotesCast, 0) as CloseVotesCast,
    coalesce(ucs.ReopenVotesCast, 0) as ReopenVotesCast,
    coalesce(ucs.DistinctPostsVoted, 0) as DistinctPostsVotedPostHistory,
    coalesce(uvs.UpVotesCast, 0) as UpVotesCast,
    coalesce(uvs.DownVotesCast, 0) as DownVotesCast,
    coalesce(uvs.FavoritesCast, 0) as FavoritesCast,
    coalesce(uvs.DistinctPostsVotedOn, 0) as DistinctPostsVotedOnVotes,
    case 
        when u.LastAccessDate > now() - interval '30 days' then 'Active'
        when u.LastAccessDate > now() - interval '180 days' then 'Inactive'
        else 'Dormant'
    end as ActivityStatus,
    length(u.AboutMe) as AboutMeLength,
    regexp_replace(
        substring(u.AboutMe from '(?i)[a-z]+'), 
        '([aeiou])', '*', 'g'
    ) as ObfuscatedAboutMeSample
from Users u
left join LatestUserPosts lub on lub.UserId = u.Id
left join UserBadgeSummary ubs on ubs.UserId = u.Id
left join UserPostStats upst on upst.UserId = u.Id
left join UserAggregatedTags ut on ut.UserId = u.Id
left join UserCloseVoteSummary ucs on ucs.UserId = u.Id
left join UserVotingStats uvs on uvs.UserId = u.Id
where u.Reputation > 5000
order by u.Reputation desc
limit 100;