-- {"query": "750.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1885} 
with RecursiveTagCounts as (
    select 
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.ViewCount,0) as ViewCount,
        coalesce(p.Score,0) as Score,
        row_number() over (partition by t.TagName order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
), 
LatestTagPosts as (
    select TagId, TagName, Count, AnswerCount, ViewCount, Score
    from RecursiveTagCounts
    where rn = 1
),
UserBadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
UserPostStats as (
    select 
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
        ups.QuestionsCount, ups.AnswersCount, ups.TotalPostScore, ups.LastPostDate,
        row_number() over (order by ups.TotalPostScore desc nulls last) as PostScoreRank,
        case when u.Location is null or trim(u.Location) = '' then 'Unknown' else u.Location end as LocationNormalized
    from Users u
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join UserPostStats ups on ups.UserId = u.Id
),
HighActivityUsers as (
    select * from UserActivity
    where QuestionsCount > 5 and AnswersCount > 10 and Reputation > 1000
),
RecentClosedQuestions as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.ClosedDate,
        p.OwnerUserId,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName
    from Posts p
    inner join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1 and p.ClosedDate is not null and p.CreationDate > cast('2024-10-01' as date) - interval '180 days'
),
UserCommentStats as (
    select 
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
UserAggregated as (
    select 
        hau.UserId,
        hau.DisplayName,
        hau.Reputation,
        hau.GoldBadges,
        hau.SilverBadges,
        hau.BronzeBadges,
        hau.QuestionsCount,
        hau.AnswersCount,
        hau.TotalPostScore,
        hau.LastPostDate,
        ucs.CommentCount,
        ucs.AvgCommentLength,
        ucs.LastCommentDate
    from HighActivityUsers hau
    left join UserCommentStats ucs on ucs.UserId = hau.UserId
),
TopUsersByActivity as (
    select 
        UserId,
        DisplayName,
        Reputation,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        QuestionsCount,
        AnswersCount,
        TotalPostScore,
        LastPostDate,
        CommentCount,
        AvgCommentLength,
        LastCommentDate,
        rank() over (order by Reputation desc, TotalPostScore desc) as ActivityRank
    from UserAggregated
),
PostWithVotes as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as BountySum
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Title, p.Tags
),
AnswerStats as (
    select 
        p.ParentId as QuestionId,
        count(p.Id) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        count(distinct p.OwnerUserId) as DistinctAnswerers
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
QuestionDetails as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        pst.AnswerCount,
        pst.AvgAnswerScore,
        pst.MaxAnswerScore,
        pst.DistinctAnswerers,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as RnkByOwner
    from PostWithVotes p
    left join AnswerStats pst on pst.QuestionId = p.Id
    where p.PostTypeId = 1
),
TopQuestionsByUser as (
    select * from QuestionDetails where RnkByOwner = 1
),
QuestionsWithDuplicates as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Score,
        pl.RelatedPostId as DuplicateOfId,
        dup.Title as DuplicateOfTitle,
        dup.Score as DuplicateOfScore
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id and pl.LinkTypeId = 3
    left join Posts dup on dup.Id = pl.RelatedPostId
    where q.PostTypeId = 1
),
UserReputationGrowth as (
    select 
        u.Id as UserId,
        u.DisplayName,
        min(p.CreationDate) as FirstPostDate,
        max(p.CreationDate) as LastPostDate,
        max(u.Reputation) - min(u.Reputation) as ReputationGrowth
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
    having count(p.Id) > 0
)
select 
    tu.ActivityRank,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges, tu.SilverBadges, tu.BronzeBadges,
    tu.QuestionsCount, tu.AnswersCount, tu.TotalPostScore,
    coalesce(tu.CommentCount,0) as CommentCount,
    coalesce(round(tu.AvgCommentLength,2),0) as AvgCommentLength,
    tu.LastCommentDate,
    q.Id as TopQuestionId,
    q.Title as TopQuestionTitle,
    q.Score as TopQuestionScore,
    q.ViewCount as TopQuestionViewCount,
    q.AnswerCount as TopQuestionAnswerCount,
    q.AvgAnswerScore as TopQuestionAvgAnswerScore,
    q.MaxAnswerScore as TopQuestionMaxAnswerScore,
    q.DistinctAnswerers as TopQuestionDistinctAnswerers,
    dq.DuplicateOfId,
    dq.DuplicateOfTitle,
    dq.DuplicateOfScore,
    rc.Id as RecentlyClosedQuestionId,
    rc.Title as RecentlyClosedQuestionTitle,
    rc.CloseReasonName,
    ur.ReputationGrowth
from TopUsersByActivity tu
left join TopQuestionsByUser q on q.OwnerUserId = tu.UserId
left join QuestionsWithDuplicates dq on dq.QuestionId = q.Id
left join RecentClosedQuestions rc on rc.OwnerUserId = tu.UserId
left join UserReputationGrowth ur on ur.UserId = tu.UserId
where tu.ActivityRank <= 50
order by tu.ActivityRank, q.Score desc nulls last, rc.ClosedDate desc nulls last
limit 100;