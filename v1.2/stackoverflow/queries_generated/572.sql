-- {"query": "572.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1889} 
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        u.Reputation as OwnerReputation,
        u.Location,
        u.CreationDate as UserCreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as UserPostRank,
        dense_rank() over (order by p.Score desc) as GlobalScoreRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2) -- questions and answers
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserActivity as (
    select
        u.Id as UserId,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        coalesce(sum(vt.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes),0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    where pl.LinkTypeId = 3 -- duplicates
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserUserName
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    left join Users u on ph.UserId = u.Id
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
),
UserReputationWindow as (
    select
        Id,
        Reputation,
        CreationDate,
        lead(Reputation) over (order by CreationDate) as NextReputation,
        lag(Reputation) over (order by CreationDate) as PrevReputation,
        lead(CreationDate) over (order by CreationDate) as NextDate,
        lag(CreationDate) over (order by CreationDate) as PrevDate
    from Users
),
PostsWithCommentCounts as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(c.CommentCount, 0) as CommentCount,
        p.Tags,
        p.OwnerUserId
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on p.Id = c.PostId
    where p.PostTypeId = 1
),
HighEngagementQuestions as (
    select
        pwc.Id,
        pwc.Title,
        pwc.CreationDate,
        pwc.Score,
        pwc.ViewCount,
        pwc.CommentCount,
        pwc.Tags,
        u.DisplayName as OwnerName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.TotalPosts,
        ua.TotalComments
    from PostsWithCommentCounts pwc
    left join Users u on pwc.OwnerUserId = u.Id
    left join UserBadgeCounts ub on pwc.OwnerUserId = ub.UserId
    left join UserActivity ua on pwc.OwnerUserId = ua.UserId
    where pwc.Score > 10 and pwc.ViewCount > 1000 and pwc.CommentCount > 5
),
TagSummary as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(pq.QuestionCount, 0) as QuestionCount,
        coalesce(pa.AnswerCount, 0) as AnswerCount,
        coalesce(avgScore.AvgQuestionScore, 0) as AvgQuestionScore,
        coalesce(avgScore.AvgAnswerScore, 0) as AvgAnswerScore
    from Tags t
    left join (
        select 
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
            count(*) as QuestionCount
        from Posts p
        where p.PostTypeId = 1
        group by TagName
    ) pq on pq.TagName = t.TagName
    left join (
        select 
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
            count(*) as AnswerCount
        from Posts p
        where p.PostTypeId = 2
        group by TagName
    ) pa on pa.TagName = t.TagName
    left join (
        select 
            TagName,
            avg(QuestionScore) as AvgQuestionScore,
            avg(AnswerScore) as AvgAnswerScore
        from (
            select 
                unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
                case when p.PostTypeId = 1 then p.Score else null end as QuestionScore,
                case when p.PostTypeId = 2 then p.Score else null end as AnswerScore
            from Posts p
        ) scores
        group by TagName
    ) avgScore on avgScore.TagName = t.TagName
)
select 
    hpq.Id as QuestionId,
    hpq.Title,
    hpq.CreationDate,
    hpq.Score,
    hpq.ViewCount,
    hpq.CommentCount,
    hpq.Tags,
    hpq.OwnerName,
    hpq.GoldBadges,
    hpq.SilverBadges,
    hpq.BronzeBadges,
    hpq.TotalPosts,
    hpq.TotalComments,
    dup.RelatedPostId as DuplicateOf,
    dup.RelatedPostTitle as DuplicateOfTitle,
    qcr.CloseReasonName,
    qcr.CloseDate,
    qcr.CloserUserName,
    ts.TagName,
    ts.QuestionCount as TagQuestions,
    ts.AnswerCount as TagAnswers,
    ts.AvgQuestionScore,
    ts.AvgAnswerScore,
    (select count(*) from Votes v where v.PostId = hpq.Id and v.VoteTypeId = 2) as UpVotes,
    (select count(*) from Votes v where v.PostId = hpq.Id and v.VoteTypeId = 3) as DownVotes,
    case 
        when hpq.Score > 50 and hpq.ViewCount > 10000 then 'High Impact'
        when hpq.Score between 20 and 50 then 'Medium Impact'
        else 'Low Impact'
    end as ImpactCategory,
    concat('Owner: ', coalesce(hpq.OwnerName,'Anonymous'), ' | Score: ', hpq.Score, ' | Views: ', hpq.ViewCount) as SummaryString
from HighEngagementQuestions hpq
left join DuplicateLinks dup on hpq.Id = dup.PostId
left join QuestionCloseReasons qcr on hpq.Id = qcr.PostId
left join TagSummary ts on ts.TagName = any(string_to_array(substring(hpq.Tags from 2 for length(hpq.Tags)-2), '><'))
where 
    (
        qcr.CloseDate is null 
        or qcr.CloseDate > hpq.CreationDate + interval '30 days'
    )
order by hpq.Score desc, hpq.ViewCount desc
limit 100;