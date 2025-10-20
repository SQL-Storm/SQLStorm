with RecursiveUserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(case when b.Class = 1 then 1 end) as GoldBadgeCount,
        count(case when b.Class = 2 then 1 end) as SilverBadgeCount,
        count(case when b.Class = 3 then 1 end) as BronzeBadgeCount,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocationRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
), LatestPostsPerUser as (
    select p.OwnerUserId, max(p.CreationDate) as LatestPostDate
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
), QuestionAnswerStats as (
    select 
        p.OwnerUserId,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        avg(nullif(p.Score,0)) filter (where p.Score is not null) as AvgScore,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as DistinctQuestions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as DistinctAnswers
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
), TopTags as (
    select 
        u.Id as UserId,
        t.TagName,
        count(*) as TagUsageCount,
        row_number() over (partition by u.Id order by count(*) desc) as TagRank
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as t(TagName)
    where p.PostTypeId = 1 and p.Tags is not null
    group by u.Id, t.TagName
), PostLinkDetails as (
    select 
        pl.PostId,
        count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
), CloseReasonAggregates as (
    select 
        p.Id as PostId,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId,
        count(case when ph.PostHistoryTypeId = 10 then 1 else null end) as CloseVotesCount,
        sum(case when ph.PostHistoryTypeId = 10 and ph.UserId is null then 1 else 0 end) as AnonymousCloseVotes
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    group by p.Id
), UserAvgActivity as (
    select 
        u.Id as UserId,
        extract(epoch from max(p.LastActivityDate) - min(p.CreationDate))/86400 as DaysActive,
        count(p.Id)*1.0 / nullif(extract(epoch from max(p.LastActivityDate) - min(p.CreationDate))/86400,0) as PostsPerDay
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    group by u.Id
), RankedUserPosts as (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as UserPostRank
    from Posts p
    where p.OwnerUserId is not null
)
select 
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.Location,
    qc.QuestionCount,
    qc.AnswerCount,
    qc.AvgScore,
    r.GoldBadgeCount,
    r.SilverBadgeCount,
    r.BronzeBadgeCount,
    lu.LatestPostDate,
    ua.DaysActive,
    ua.PostsPerDay,
    array_agg(tt.TagName) filter (where tt.TagRank <= 3) as Top3Tags,
    (
        select avg(CASE WHEN pld.DuplicateCount = 0 THEN null ELSE (pld.LinkedCount * 1.0) / pld.DuplicateCount END)
        from Posts p2
        join PostLinkDetails pld on pld.PostId = p2.Id
        where p2.OwnerUserId = r.UserId
    ) as AvgLinkedToDuplicateRatio,
    (
        select count(*) from Posts p3 
        join CloseReasonAggregates cra on cra.PostId = p3.Id
        where p3.OwnerUserId = r.UserId and cra.CloseVotesCount > 0 and cra.CloseReasonId in (101,103)
    ) as ImportantCloseVotesCount,
    max(case when rb.UserPostRank = 1 then rb.Score else null end) as HighestScorePost,
    min(case when rb.UserPostRank = 1 then rb.CreationDate else null end) as HighestScorePostDate
from RecursiveUserBadgeCounts r
left join QuestionAnswerStats qc on qc.OwnerUserId = r.UserId
left join LatestPostsPerUser lu on lu.OwnerUserId = r.UserId
left join UserAvgActivity ua on ua.UserId = r.UserId
left join TopTags tt on tt.UserId = r.UserId
left join RankedUserPosts rb on rb.OwnerUserId = r.UserId
where r.Location is not null and r.Location <> ''
group by r.UserId, r.DisplayName, r.Reputation, r.Location, qc.QuestionCount, qc.AnswerCount, qc.AvgScore, r.GoldBadgeCount, r.SilverBadgeCount, r.BronzeBadgeCount, lu.LatestPostDate, ua.DaysActive, ua.PostsPerDay
order by r.Reputation desc, ImportantCloseVotesCount desc
limit 100;