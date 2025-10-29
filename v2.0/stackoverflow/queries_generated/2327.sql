-- {"query": "2327.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1524} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
),
TopScoringAnswers as (
    select
        p.Id,
        p.ParentId,
        p.OwnerUserId,
        p.Score
    from Posts p
    where p.PostTypeId = 2 -- answers only
    and p.Score > (
        select avg(p2.Score) from Posts p2
        where p2.PostTypeId = 2 and p2.ParentId = p.ParentId
    )
),
PostCommentsSummary as (
    select
        c.PostId,
        count(c.Id) as CommentCount,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
        sum(case when c.Score <= 0 or c.Score is null then 1 else 0 end) as NonPositiveComments,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ',' order by c.CreationDate desc) as RecentCommenters
    from Comments c
    group by c.PostId
),
UserPostActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        max(p.CreationDate) filter (where p.PostTypeId in (1,2)) as LastPostDate,
        min(p.CreationDate) filter (where p.PostTypeId in (1,2)) as FirstPostDate,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserPostLinkStats as (
    select
        p.OwnerUserId as UserId,
        sum(case when l.LinkTypeId = 1 then 1 else 0 end) as TotalLinkedPosts,
        sum(case when l.LinkTypeId = 3 then 1 else 0 end) as TotalDuplicatePosts
    from Posts p
    left join PostLinks l on l.PostId = p.Id
    group by p.OwnerUserId
),
UserBadgesBeforeDate as (
    select 
        b.UserId,
        count(*) filter (where b.Date < '2023-01-01') as BadgesBefore2023,
        count(*) filter (where b.Date >= '2023-01-01') as BadgesAfter2023
    from Badges b
    group by b.UserId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(pub.QuestionCount, 0) as QuestionCount,
    coalesce(pub.AnswerCount, 0) as AnswerCount,
    coalesce(pub.TotalPostScore, 0) as TotalPostScore,
    coalesce(pub.AvgPostScore, 0) as AvgPostScore,
    rbc.GoldBadges,
    rbc.SilverBadges,
    rbc.BronzeBadges,
    up.LinksToPosts,
    coalesce(ups.TotalLinkedPosts, 0) as TotalLinkedPosts,
    coalesce(ups.TotalDuplicatePosts, 0) as TotalDuplicatePosts,
    coalesce(upb.BadgesBefore2023, 0) as BadgesBefore2023,
    coalesce(upb.BadgesAfter2023, 0) as BadgesAfter2023,
    pcs.CloseReason,
    pcs.CloseDate,
    pc.CommentCount,
    pc.PositiveComments,
    pc.NonPositiveComments,
    pc.RecentCommenters,
    rp.Title as LatestPostTitle,
    rp.CreationDate as LatestPostCreationDate,
    rp.Score as LatestPostScore,
    case
        when rp.Score is null then null
        when rp.Score < 0 then 'Negative'
        when rp.Score = 0 then 'Neutral'
        when rp.Score between 1 and 10 then 'Positive'
        else 'Highly Positive'
    end as LatestPostScoreCategory,
    ts.AnswerScoreRank,
    ts.AnswerCountAboveAvg
from Users u
left join RecursiveUserBadgeCounts rbc on rbc.UserId = u.Id
left join UserPostActivity pub on pub.UserId = u.Id
left join PostCommentsSummary pc on pc.PostId = (
    select p2.Id from Posts p2
    where p2.OwnerUserId = u.Id and p2.PostTypeId in (1,2)
    order by p2.CreationDate desc
    limit 1
)
left join (
    select
        tpa.OwnerUserId,
        count(tpa.Id) as AnswerCountAboveAvg,
        max(RankedPosts.ScoreRank) as AnswerScoreRank
    from TopScoringAnswers tpa
    join RankedPosts on RankedPosts.Id = tpa.Id
    group by tpa.OwnerUserId
) ts on ts.OwnerUserId = u.Id
left join RankedPosts rp on rp.OwnerUserId = u.Id and rp.RecentPostRank = 1
left join QuestionCloseReasons pcs on pcs.PostId = (
    select p3.Id from Posts p3
    where p3.OwnerUserId = u.Id and p3.PostTypeId = 1
    order by p3.CreationDate desc
    limit 1
)
left join UserPostLinkStats ups on ups.UserId = u.Id
left join UserBadgesBeforeDate upb on upb.UserId = u.Id
order by u.Reputation desc
limit 100;