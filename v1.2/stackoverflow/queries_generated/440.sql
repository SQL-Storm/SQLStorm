-- {"query": "440.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1264} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        coalesce(p.Score, 0) as TotalScore
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.Count > 100
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        rtc.TotalAnswers + coalesce(p2.AnswerCount, 0),
        rtc.TotalViews + coalesce(p2.ViewCount, 0),
        rtc.TotalScore + coalesce(p2.Score, 0)
    from Tags t2
    join RecursiveTagCounts rtc on rtc.TagId <> t2.Id and rtc.Count > 100
    left join Posts p2 on p2.Id = t2.ExcerptPostId and p2.PostTypeId = 1
    where t2.Count > 100 and t2.Id > rtc.TagId
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        sum(v.VoteTypeId = 2::int)::int as UpVotesReceived,
        sum(v.VoteTypeId = 3::int)::int as DownVotesReceived,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        count(distinct b.Id) as BadgesEarned
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        rank() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.CreationDate desc nulls last) as RecentRank
    from Posts p
    where p.Score is not null
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        count(c.Id) as CommentCount,
        string_agg(distinct c.Text, ' || ') filter (where c.Text is not null) as CommentsText,
        max(c.CreationDate) as LastCommentDate
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.Tags, p.OwnerUserId, p.CreationDate
    having count(c.Id) > 5
),
UserBadgesRanked as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
),
UserTopBadges as (
    select
        ubr.UserId,
        string_agg(ubr.BadgeName || ' (' || case ubr.Class when 1 then 'Gold' when 2 then 'Silver' else 'Bronze' end || ')', ', ') as TopBadges
    from UserBadgesRanked ubr
    where ubr.BadgeRank <= 3
    group by ubr.UserId
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ua.BadgesEarned,
    ua.FirstPostDate,
    ua.LastPostDate,
    utb.TopBadges,
    p.Id as TopPostId,
    p.Title as TopPostTitle,
    p.Score as TopPostScore,
    p.ViewCount as TopPostViews,
    p.AnswerCount as TopPostAnswerCount,
    p.CommentCount as TopPostCommentCount,
    p.CommentsText as TopPostComments,
    p.LastCommentDate as TopPostLastCommentDate,
    rtc.TagName as PopularTag,
    rtc.Count as TagUsageCount,
    rtc.TotalAnswers as TagTotalAnswers,
    rtc.TotalViews as TagTotalViews,
    rtc.TotalScore as TagTotalScore
from UserActivity ua
left join UserTopBadges utb on utb.UserId = ua.UserId
left join lateral (
    select p2.*
    from TopPostsWithComments p2
    where p2.OwnerUserId = ua.UserId
    order by p2.Score desc nulls last, p2.ViewCount desc nulls last
    limit 1
) p on true
left join lateral (
    select rtc2.*
    from RecursiveTagCounts rtc2
    order by rtc2.Count desc nulls last, rtc2.TotalScore desc nulls last
    limit 1
) rtc on true
where ua.Reputation > 1000
and (ua.QuestionsPosted > 10 or ua.AnswersPosted > 20)
and (p.Score is null or p.Score > 5)
order by ua.Reputation desc, ua.AnswersPosted desc
limit 50;