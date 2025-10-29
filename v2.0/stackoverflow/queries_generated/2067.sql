-- {"query": "2067.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1567} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as AncestorPath
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select 
        t2.Id,
        t2.TagName,
        t2.Count,
        r.AncestorPath || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on array_position(r.AncestorPath, t2.Id) is null and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
    where t2.Count < r.Count
    limit 100
),
UserBadgeRanks as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId 
    group by u.Id, u.DisplayName, u.Reputation, b.Class
),
UserPostScores as (
    select 
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(*) filter (where p.PostTypeId = 2) as AnswersCount,
        sum(p.Score) as TotalPostScore,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAcceptedAnswerCount,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
),
PostRankings as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        rank() over (partition by p.PostTypeId order by p.AnswerCount desc nulls last) as AnswerCountRank
    from posts p
    where p.PostTypeId in (1, 2) -- Questions and Answers
),
CloseReasonCounts as (
    select 
        cht.Name as CloseReasonName,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes cht_types on ph.PostHistoryTypeId = cht_types.Id
    join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$'
    group by cht.Name
    order by CloseCount desc
),
QualifiedPosts as (
    select p.Id, p.Title, p.Tags, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1) as TagCount
    from posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000 and p.Tags is not null
),
RecentCommentsPerPost as (
    select 
        c.PostId,
        c.Text,
        c.CreationDate,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as rn
    from comments c
),
PostsWithLatestComment as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        rc.Text as LatestCommentText,
        rc.CreationDate as LatestCommentDate
    from QualifiedPosts q
    left join RecentCommentsPerPost rc on q.Id = rc.PostId and rc.rn = 1
),
UserActivitySummary as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as Questions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as Answers,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vt_count.Upvotes),0) as TotalUpvotesReceived,
        coalesce(sum(vt_count.Downvotes),0) as TotalDownvotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select
            p.OwnerUserId as OwnerUserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as Upvotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as Downvotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        join Posts p on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt_count on vt_count.OwnerUserId = u.Id
    where u.Id is not null
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
)
select 
    pas.DisplayName,
    pas.Reputation,
    pas.TotalPosts,
    pas.Questions,
    pas.Answers,
    pas.CommentsMade,
    pas.TotalUpvotesReceived,
    pas.TotalDownvotesReceived,
    coalesce(ubr_badge_gold.BadgeCount,0) as GoldBadges,
    coalesce(ubr_badge_silver.BadgeCount,0) as SilverBadges,
    coalesce(ubr_badge_bronze.BadgeCount,0) as BronzeBadges,
    json_agg(json_build_object(
        'PostId', pq.Id,
        'Title', pq.Title,
        'Score', pq.Score,
        'ViewCount', pq.ViewCount,
        'TagCount', pq.TagCount,
        'LatestComment', pwlc.LatestCommentText
    ) order by pq.Score desc) filter (where pq.Id is not null) as TopPosts
from UserActivitySummary pas
left join UserBadgeRanks ubr_badge_gold on pas.Id = ubr_badge_gold.UserId and ubr_badge_gold.Class = 1
left join UserBadgeRanks ubr_badge_silver on pas.Id = ubr_badge_silver.UserId and ubr_badge_silver.Class = 2
left join UserBadgeRanks ubr_badge_bronze on pas.Id = ubr_badge_bronze.UserId and ubr_badge_bronze.Class = 3
left join LATERAL (
    select q.*
    from Posts q
    where q.OwnerUserId = pas.Id and q.Score > 50
    order by q.Score desc
    limit 5
) pq on true
left join PostsWithLatestComment pwlc on pq.Id = pwlc.QuestionId
where pas.TotalPosts > 100
group by pas.Id, pas.DisplayName, pas.Reputation, pas.TotalPosts, pas.Questions, pas.Answers, pas.CommentsMade, pas.TotalUpvotesReceived, pas.TotalDownvotesReceived, ubr_badge_gold.BadgeCount, ubr_badge_silver.BadgeCount, ubr_badge_bronze.BadgeCount
order by pas.Reputation desc
limit 20;