-- {"query": "2917.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1271} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        p.Id as PostId,
        1 as Depth
    from Tags t
    join Posts p on p.Tags like '%' || t.TagName || '%'
    where t.IsModeratorOnly = 0
    union all
    select
        rtc.TagId,
        rtc.TagName,
        pl.RelatedPostId,
        rtc.Depth + 1
    from RecursiveTagCounts rtc
    join PostLinks pl on pl.PostId = rtc.PostId
    where rtc.Depth < 3
),
UserBadgeSummary as (
    select
        b.UserId,
        -- complex badge score weighted by Class and TagBased
        sum(case when b.TagBased = 1 then 5 * (4 - b.Class) else 3 * (4 - b.Class) end) as BadgeScore,
        count(distinct b.Name) as DistinctBadges,
        max(b.Date) as MostRecentBadge
    from Badges b
    group by b.UserId
),
UserPostStats as (
    select
        u.Id as UserId,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        avg(case when p.Score is not null then p.Score else 0 end) as AvgPostScore,
        max(p.ViewCount) as MaxViewCount,
        sum(p.FavoriteCount) as TotalFavorites,
        bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
RankedUserActivity as (
    select
        ups.UserId,
        ups.QuestionsCount,
        ups.AnswersCount,
        ups.AvgPostScore,
        ups.MaxViewCount,
        ups.TotalFavorites,
        ups.HasClosedPosts,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        u.WebsiteUrl,
        u.AboutMe,
        u.ProfileImageUrl,
        u.AccountId,
        u.EmailHash,
        ubs.BadgeScore,
        ubs.DistinctBadges,
        ubs.MostRecentBadge,
        row_number() over (order by ups.AnswersCount desc, ups.QuestionsCount desc, u.Reputation desc nulls last) as ActivityRank
    from UserPostStats ups
    join Users u on u.Id = ups.UserId
    left join UserBadgeSummary ubs on ubs.UserId = ups.UserId
),
UserRecentComments as (
    select
        c.UserId,
        array_agg(distinct substring(c.Text from 1 for 30) order by c.CreationDate desc) as RecentCommentSamples,
        count(c.Id) as CommentCount
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
TopTagsPerUser as (
    select
        p.OwnerUserId as UserId,
        tag.TagName,
        count(*) as TagUseCount,
        rank() over (partition by p.OwnerUserId order by count(*) desc) as TagRank
    from Posts p
    cross join lateral (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName
    ) tag
    where p.PostTypeId = 1 and p.Tags is not null
    group by p.OwnerUserId, tag.TagName
),
ConsolidatedTopTags as (
    select
        UserId,
        string_agg(TagName || ':' || TagUseCount, ', ' order by TagUseCount desc) as TopTags
    from TopTagsPerUser
    where TagRank <= 3
    group by UserId
)
select
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.ActivityRank,
    ru.QuestionsCount,
    ru.AnswersCount,
    ru.AvgPostScore,
    ru.MaxViewCount,
    ru.TotalFavorites,
    ru.HasClosedPosts,
    coalesce(ubs.BadgeScore, 0) as BadgeScore,
    coalesce(ubs.DistinctBadges, 0) as BadgeCount,
    ru.MostRecentBadge,
    rc.CommentCount,
    rc.RecentCommentSamples,
    ct.TopTags,
    -- determine if user location is US or contains NULL
    case 
        when ru.Location is null then 'Location Unknown'
        when ru.Location ~* 'usa|united states|us' then 'United States'
        else 'Other'
    end as LocationGroup,
    -- complex string manipulation: create a user summary snippet
    left(
        concat_ws(' | ',
            ru.DisplayName,
            'Rep: ' || ru.Reputation,
            'Posts: ' || (ru.QuestionsCount + ru.AnswersCount),
            'Badges: ' || coalesce(ubs.DistinctBadges::text, '0'),
            'Top Tags: ' || coalesce(ct.TopTags, 'None')
        ), 200) as UserSummary,
    -- Window function: ranking of users by BadgeScore within LocationGroup
    rank() over (partition by 
        case 
            when ru.Location is null then 'Unknown' 
            when ru.Location ~* 'usa|united states|us' then 'USA' 
            else 'Other' 
        end
        order by coalesce(ubs.BadgeScore,0) desc) as LocationBadgeRank
from RankedUserActivity ru
left join UserBadgeSummary ubs on ubs.UserId = ru.UserId
left join UserRecentComments rc on rc.UserId = ru.UserId
left join ConsolidatedTopTags ct on ct.UserId = ru.UserId
where ru.ActivityRank <= 100
order by ru.ActivityRank, LocationBadgeRank;