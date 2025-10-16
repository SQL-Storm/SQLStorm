-- {"query": "655.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1426} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserBadgeSummary as (
    select 
        b.UserId,
        count(*) as BadgeCount,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadges
    from Badges b
    group by b.UserId
),
PostQuestionDetails as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserTopQuestionRank
    from Posts p
    where p.PostTypeId = 1
),
AnswerDetails as (
    select 
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        p.Title as ParentQuestionTitle,
        dense_rank() over (partition by a.ParentId order by a.Score desc nulls last) as AnswerScoreRank
    from Posts a
    left join Posts p on p.Id = a.ParentId
    where a.PostTypeId = 2
),
DuplicateQuestions as (
    select distinct pl.PostId as DuplicateId, pl.RelatedPostId as OriginalId
    from PostLinks pl
    where pl.LinkTypeId = 3
),
QuestionCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserActivityWindow as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct a.Id) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        row_number() over (order by u.Reputation desc nulls last) as ReputationRank,
        rank() over (partition by u.Location order by u.Reputation desc nulls last) as LocationReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.Location
),
TopPostsWithBadges as (
    select 
        pqd.Id,
        pqd.Title,
        pqd.Score,
        pqd.ViewCount,
        pqd.Tags,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        coalesce(ubs.BadgeCount, 0) as OwnerBadgeCount,
        coalesce(ubs.GoldBadges, 0) as OwnerGoldBadges,
        coalesce(ubs.SilverBadges, 0) as OwnerSilverBadges,
        coalesce(ubs.BronzeBadges, 0) as OwnerBronzeBadges,
        u.Location,
        qcr.CloseReasonName,
        qcr.CloseDate,
        dup.OriginalId as DuplicateOfQuestionId
    from PostQuestionDetails pqd
    left join Users u on u.Id = pqd.OwnerUserId
    left join UserBadgeSummary ubs on ubs.UserId = u.Id
    left join QuestionCloseReasons qcr on qcr.PostId = pqd.Id
    left join DuplicateQuestions dup on dup.DuplicateId = pqd.Id
    where pqd.Score > 10 and pqd.ViewCount > 1000
)
select 
    tp.Id as QuestionId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    regexp_replace(tp.Tags, '[<>]', ' ', 'g') as ParsedTags,
    tp.OwnerName,
    tp.OwnerReputation,
    tp.OwnerBadgeCount,
    tp.OwnerGoldBadges,
    tp.OwnerSilverBadges,
    tp.OwnerBronzeBadges,
    tp.Location,
    tp.CloseReasonName,
    tp.CloseDate,
    tp.DuplicateOfQuestionId,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.ReputationRank,
    ua.LocationReputationRank,
    avg(a.Score) over (partition by tp.Id) as AvgAnswerScore,
    max(a.Score) over (partition by tp.Id) as MaxAnswerScore,
    count(a.Id) over (partition by tp.Id) as AnswerCount,
    case 
        when tp.CloseDate is not null then 'Closed'
        when tp.DuplicateOfQuestionId is not null then 'Duplicate'
        else 'Open'
    end as QuestionStatus,
    case 
        when ua.Reputation > 10000 then 'Expert'
        when ua.Reputation between 1000 and 10000 then 'Intermediate'
        else 'Beginner'
    end as UserExperienceLevel
from TopPostsWithBadges tp
left join AnswerDetails a on a.ParentId = tp.Id
left join UserActivityWindow ua on ua.Id = tp.OwnerName::int
where tp.OwnerReputation > 500
order by tp.Score desc, tp.ViewCount desc
limit 100;