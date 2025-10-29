-- {"query": "2202.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1572} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        p.CreationDate,
        row_number() over (partition by t.Id order by p.CreationDate desc nulls last) as RN
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
),
LatestTagActivity as (
    select
        Id,
        TagName,
        Count,
        TotalAnswers,
        CreationDate
    from RecursiveTagCounts
    where RN = 1
),
UserBadgeSummary as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        min(Date) as FirstBadgeDate,
        max(Date) as LastBadgeDate
    from Badges
    group by UserId
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopPostsWithComments as (
    select
        p.Id as PostId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        count(c.Id) as CommentCount,
        string_agg(distinct coalesce(c.UserDisplayName, 'Unknown'), ', ') as Commenters,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
),
FilteredTopPosts as (
    select
        PostId,
        Title,
        OwnerUserId,
        Score,
        ViewCount,
        CreationDate,
        CommentCount,
        Commenters
    from TopPostsWithComments
    where PostRank <= 3
),
QuestionsWithAcceptedVsAvgAnswer as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        avg(ans.Score) as AvgAnswerScore,
        (
            select count(*) 
            from Votes v 
            where v.PostId = q.Id and v.VoteTypeId = 15 -- ModeratorReview votes
        ) as ModeratorReviewsCount
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Posts ans on ans.ParentId = q.Id and ans.Id != q.AcceptedAnswerId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.Score, a.Id, a.Score
),
DistinctUserPairs as (
    select distinct
        least(pl.PostId, pl.RelatedPostId) as User1Post,
        greatest(pl.PostId, pl.RelatedPostId) as User2Post,
        pl.CreationDate,
        pl.LinkTypeId
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where p1.OwnerUserId is not null and p2.OwnerUserId is not null
),
UserInteractionSummary as (
    select
        p1.OwnerUserId as User1Id,
        p2.OwnerUserId as User2Id,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        max(pl.CreationDate) as LastInteraction
    from DistinctUserPairs pl
    join Posts p1 on p1.Id = pl.User1Post
    join Posts p2 on p2.Id = pl.User2Post
    group by p1.OwnerUserId, p2.OwnerUserId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AvgPostScore,
    ups.MaxPostScore,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TotalBadges,
    ubs.FirstBadgeDate,
    ubs.LastBadgeDate,
    lt.TagName as LatestActiveTag,
    lt.Count as TagPopularity,
    lt.TotalAnswers as TagAnswerVolume,
    ftp.PostId,
    ftp.Title as TopPostTitle,
    ftp.Score as TopPostScore,
    ftp.ViewCount as TopPostViewCount,
    ftp.CommentCount as TopPostCommentCount,
    ftp.Commenters as TopPostCommenters,
    qava.QuestionId,
    qava.Title as QuestionTitle,
    qava.QuestionScore,
    qava.AcceptedAnswerId,
    qava.AcceptedAnswerScore,
    qava.AvgAnswerScore,
    qava.ModeratorReviewsCount,
    uis.LinkedCount,
    uis.DuplicateCount,
    uis.LastInteraction,
    case
        when ups.HasClosedPosts then 'Some Closed Posts'
        when ups.AnswerCount > ups.QuestionCount then 'Answerer'
        when ups.AnswerCount = 0 and ups.QuestionCount = 0 then 'New User'
        else 'Question Asker'
    end as UserCategory
from Users u
left join UserPostStats ups on ups.UserId = u.Id
left join UserBadgeSummary ubs on ubs.UserId = u.Id
left join LatestTagActivity lt on lt.Id = (
    select TagId from (
        select t.Id as TagId,
            row_number() over (partition by t.Id order by lt.CreationDate desc nulls last) as rnk
        from Tags t
        join LatestTagActivity lt on lt.TagName = t.TagName
        where t.Id is not null
    ) sub where sub.rnk = 1 limit 1
)
left join FilteredTopPosts ftp on ftp.OwnerUserId = u.Id
left join QuestionsWithAcceptedVsAvgAnswer qava on qava.OwnerUserId = u.Id
left join UserInteractionSummary uis on uis.User1Id = u.Id
where u.Reputation > 1000 and u.DisplayName is not null
order by u.Reputation desc, u.Id
limit 50;