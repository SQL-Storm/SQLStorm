-- {"query": "78.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1692} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as RepRank
    from Users u
    left join UserBadgeCounts ubc_gold on u.Id = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on u.Id = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on u.Id = ubc_bronze.UserId and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByRegisteredUsers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
QuestionComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.UserId is null then 0 else 1 end) as CommentsByRegisteredUsers,
        string_agg(distinct substring(c.Text from 1 for 20), ' | ') as SampleComments
    from Comments c
    group by c.PostId
),
QuestionAggregates as (
    select
        tq.Id,
        tq.Title,
        tq.OwnerUserId,
        tq.OwnerName,
        tq.Score,
        tq.ViewCount,
        tq.CreationDate,
        tq.Tags,
        tq.AcceptedAnswerId,
        asn.AnswerCount,
        asn.AvgAnswerScore,
        asn.MaxAnswerScore,
        asn.AnsweredByRegisteredUsers,
        qcr.CloseReasonName,
        qcr.CloseDate,
        qc.CommentCount,
        qc.CommentsByRegisteredUsers,
        qc.SampleComments
    from TopQuestions tq
    left join AnswerStats asn on tq.Id = asn.QuestionId
    left join QuestionCloseReasons qcr on tq.Id = qcr.PostId
    left join QuestionComments qc on tq.Id = qc.PostId
),
RankedQuestions as (
    select
        qa.*,
        row_number() over (partition by qa.OwnerUserId order by qa.Score desc, qa.ViewCount desc) as OwnerQuestionRank,
        count(*) over (partition by qa.OwnerUserId) as OwnerQuestionCount
    from QuestionAggregates qa
),
FinalSelection as (
    select
        rq.Id as QuestionId,
        rq.Title,
        rq.OwnerUserId,
        rq.OwnerName,
        rq.Score,
        rq.ViewCount,
        rq.CreationDate,
        rq.Tags,
        rq.AcceptedAnswerId,
        rq.AnswerCount,
        rq.AvgAnswerScore,
        rq.MaxAnswerScore,
        rq.AnsweredByRegisteredUsers,
        rq.CloseReasonName,
        rq.CloseDate,
        rq.CommentCount,
        rq.CommentsByRegisteredUsers,
        rq.SampleComments,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        ur.Reputation,
        ur.RepRank,
        string_agg(distinct rth.TagName, ', ') as RelatedTags
    from RankedQuestions rq
    join UserReputationStats ur on rq.OwnerUserId = ur.UserId
    left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(rq.Tags, '')) > 0
    where rq.OwnerQuestionRank <= 3
    group by
        rq.Id, rq.Title, rq.OwnerUserId, rq.OwnerName, rq.Score, rq.ViewCount, rq.CreationDate, rq.Tags, rq.AcceptedAnswerId,
        rq.AnswerCount, rq.AvgAnswerScore, rq.MaxAnswerScore, rq.AnsweredByRegisteredUsers, rq.CloseReasonName, rq.CloseDate,
        rq.CommentCount, rq.CommentsByRegisteredUsers, rq.SampleComments,
        ur.GoldBadges, ur.SilverBadges, ur.BronzeBadges, ur.Reputation, ur.RepRank
)
select
    fs.QuestionId,
    fs.Title,
    fs.OwnerName,
    fs.Reputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.Score,
    fs.ViewCount,
    fs.AnswerCount,
    round(fs.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    fs.MaxAnswerScore,
    fs.AnsweredByRegisteredUsers,
    coalesce(fs.CloseReasonName, 'Open') as CloseStatus,
    fs.CloseDate,
    fs.CommentCount,
    fs.CommentsByRegisteredUsers,
    left(fs.SampleComments, 200) as SampleComments,
    fs.RelatedTags,
    -- Complex string expression combining tags and title length
    case
        when length(fs.Title) > 100 then 'Long Title'
        when fs.AnswerCount > 5 then 'Popular Question'
        else 'Regular Question'
    end as QuestionCategory,
    -- Window function to calculate percentile rank of score among all questions
    percentile_cont(0.9) within group (order by fs.Score) over () as Score90Percentile,
    -- Correlated subquery to find the latest comment date for the question
    (select max(c.CreationDate) from Comments c where c.PostId = fs.QuestionId) as LatestCommentDate,
    -- NULL logic example: if no accepted answer, fallback to max answer score
    coalesce(
        (select p.Score from Posts p where p.Id = fs.AcceptedAnswerId),
        fs.MaxAnswerScore,
        0
    ) as AcceptedOrMaxAnswerScore
from FinalSelection fs
order by fs.Reputation desc, fs.Score desc, fs.ViewCount desc
limit 50;