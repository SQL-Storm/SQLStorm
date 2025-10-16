-- {"query": "160.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1405} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        sum(v.VoteCount) as TotalVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate

    union all

    select
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.CreationDate,
        ru.LastAccessDate,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.CommentCount,
        ru.BadgeCount,
        ru.TotalVotesReceived
    from RecursiveUserActivity ru
    where ru.Reputation > 1000
    limit 100
),
PostWithHistory as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.Comment as HistoryComment,
        crt.Name as CloseReasonName
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (10,11)
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
),
RankedPosts as (
    select
        pwh.*,
        row_number() over (partition by pwh.OwnerUserId order by pwh.Score desc nulls last, pwh.ViewCount desc nulls last) as PostRank,
        count(*) over (partition by pwh.OwnerUserId) as TotalPostsByUser
    from PostWithHistory pwh
    where pwh.PostTypeId in (1,2)
),
TopTags as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    order by TagCount desc
    limit 10
),
UserTagActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        t.Tag,
        count(p.Id) as PostsWithTag
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as t(Tag)
    group by u.Id, u.DisplayName, t.Tag
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Badges b
    group by b.UserId
),
UserScoreStats as (
    select
        p.OwnerUserId as UserId,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        min(p.Score) as MinPostScore,
        stddev_samp(p.Score) as StdDevPostScore
    from Posts p
    where p.PostTypeId in (1,2)
    group by p.OwnerUserId
)
select
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.CommentCount,
    ru.BadgeCount,
    ru.TotalVotesReceived,
    uts.AvgPostScore,
    uts.MaxPostScore,
    uts.MinPostScore,
    uts.StdDevPostScore,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    coalesce(ubs.TagBasedBadges,0) as TagBasedBadges,
    array_agg(distinct uta.Tag order by count(uta.PostsWithTag) desc nulls last) filter (where uta.UserId = ru.UserId) as TopUserTags,
    rp.PostRank,
    rp.Title as TopPostTitle,
    rp.Score as TopPostScore,
    rp.ViewCount as TopPostViews,
    rp.CloseReasonName,
    tt.Tag as PopularTag,
    tt.TagCount
from RecursiveUserActivity ru
left join UserScoreStats uts on uts.UserId = ru.UserId
left join UserBadgeSummary ubs on ubs.UserId = ru.UserId
left join UserTagActivity uta on uta.UserId = ru.UserId
left join RankedPosts rp on rp.OwnerUserId = ru.UserId and rp.PostRank = 1
cross join TopTags tt
where ru.Reputation > 500
group by
    ru.UserId, ru.DisplayName, ru.Reputation, ru.QuestionCount, ru.AnswerCount, ru.CommentCount, ru.BadgeCount, ru.TotalVotesReceived,
    uts.AvgPostScore, uts.MaxPostScore, uts.MinPostScore, uts.StdDevPostScore,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TagBasedBadges,
    rp.PostRank, rp.Title, rp.Score, rp.ViewCount, rp.CloseReasonName,
    tt.Tag, tt.TagCount
order by ru.Reputation desc, rp.Score desc
limit 50;