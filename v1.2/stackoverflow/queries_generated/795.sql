-- {"query": "795.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1438} 
with RecursiveTags as (
    select 
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 -- questions only
),
BadgesPerUser as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges
    from Badges
    group by UserId
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(bp.GoldBadges,0) as GoldBadges,
        coalesce(bp.SilverBadges,0) as SilverBadges,
        coalesce(bp.BronzeBadges,0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        sum(v.VoteTypeId = 2)::int as UpVotesReceived,
        sum(v.VoteTypeId = 3)::int as DownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join BadgesPerUser bp on bp.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, bp.GoldBadges, bp.SilverBadges, bp.BronzeBadges
),
PostWithLinkInfo as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        pl.LinkTypeId,
        pl.RelatedPostId
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
),
WindowedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as Rnk,
        dense_rank() over (order by p.Score desc nulls last) as DenseRnk
    from Posts p
    where p.PostTypeId in (1,2)
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
CorrelatedAnswerCount as (
    select
        q.Id as QuestionId,
        (select count(*) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as AnswerCount
    from Posts q
    where q.PostTypeId = 1
),
ComplexAggregates as (
    select
        u.UserId,
        u.DisplayName,
        count(distinct q.Id) filter (where q.Score > 10) as HighScoreQuestions,
        count(distinct a.Id) filter (where a.Score > 5) as HighScoreAnswers,
        coalesce(sum(vb.BountyAmount),0) as TotalBountyEarned,
        max(vb.BountyAmount) as MaxSingleBounty,
        string_agg(distinct t.TagName, ',' order by t.TagName) as TagList,
        avg(case when q.ClosedDate is null then 1.0 else 0.0 end) as OpenQuestionRatio
    from Users u
    left join Posts q on q.OwnerUserId = u.UserId and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.UserId and a.PostTypeId = 2
    left join Votes vb on vb.PostId = a.Id and vb.VoteTypeId = 8 -- BountyStart votes on answers
    left join RecursiveTags t on t.PostId = q.Id
    group by u.UserId, u.DisplayName
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AvgPostScore,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ca.AnswerCount as AnswersPerQuestion,
    cq.CloseReason,
    cq.CloseDate,
    wp.Rnk as UserPostRankByScore,
    wp.DenseRnk as GlobalPostDenseRank,
    caq.AnswerCount as CorrelatedAnswerCount,
    caq.QuestionId,
    caq.AnswerCount as AnswerCountForQuestion,
    ca.HighScoreQuestions,
    ca.HighScoreAnswers,
    ca.TotalBountyEarned,
    ca.MaxSingleBounty,
    ca.TagList,
    ca.OpenQuestionRatio
from UserActivity ua
left join (
    select OwnerUserId, avg(AnswerCount) as AnswerCount
    from (
        select q.OwnerUserId, count(a.Id) as AnswerCount
        from Posts q
        left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
        where q.PostTypeId = 1
        group by q.OwnerUserId, q.Id
    ) sub
    group by OwnerUserId
) ca on ca.OwnerUserId = ua.UserId
left join ClosedQuestionsWithReasons cq on cq.PostId = (
    select Id from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1 and p.ClosedDate is not null limit 1
)
left join WindowedPosts wp on wp.OwnerUserId = ua.UserId and wp.Rnk = 1
left join CorrelatedAnswerCount caq on caq.QuestionId = wp.Id
left join ComplexAggregates ca on ca.UserId = ua.UserId
where ua.Reputation > 1000
order by ua.Reputation desc, ua.GoldBadges desc
limit 100;