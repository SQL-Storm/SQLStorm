-- {"query": "1175.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1284} 
with RecursivePostTagAgg as (
    select 
        p.Id as PostId,
        regexp_split_to_table(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') as Tag,
        row_number() over(partition by p.Id order by p.CreationDate desc) as TagRank,
        p.CreationDate,
        p.Score,
        p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1
), LatestTagPerPost as (
    select PostId, Tag
    from RecursivePostTagAgg
    where TagRank = 1
), UserScoreAgg as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalQuestions,
        coalesce(sum(p.Score),0) as SumScore,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        dense_rank() over(order by count(distinct p.Id) desc) as RankByQuestions,
        min(p.CreationDate) as FirstQuestionDate,
        max(p.CreationDate) as LastQuestionDate,
        -- average time between questions: use lag
        avg(julianday(p.CreationDate) - julianday(lag(p.CreationDate) over (partition by u.Id order by p.CreationDate))) as AvgDaysBetweenQuestions
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
), TopUsersAnswers as (
    select
        a.OwnerUserId as UserId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.CreationDate) as LastAnswerDate
    from Posts a
    where a.PostTypeId = 2
    group by a.OwnerUserId
), DuplicateQuestions as (
    select distinct pl.PostId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
), QuestionCloseReasons as (
    select ph.PostId, crt.Name as CloseReason, max(ph.CreationDate) as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and crt.Id is not null -- only closed posts with known reasons
    group by ph.PostId, crt.Name
), AnswerRanks as (
    select
        a.Id, a.ParentId, a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRanking
    from Posts a
    where a.PostTypeId = 2
), TopAnswersWithComments as (
    select
        ar.*,
        count(c.Id) as CommentCount,
        coalesce(sum(case when c.UserId = ar.OwnerUserId then 1 else 0 end), 0) as CommentsByOwner
    from AnswerRanks ar
    left join Posts p on p.Id = ar.Id
    left join Comments c on c.PostId = ar.Id
    group by ar.Id, ar.ParentId, ar.Score, ar.AnswerRanking, p.OwnerUserId
    having ar.AnswerRanking <= 3
)
select 
    us.UserId,
    us.DisplayName,
    us.TotalQuestions,
    us.SumScore,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    coalesce(tua.AnswerCount,0) as AnswerCount,
    coalesce(tua.AvgAnswerScore,0)::numeric(8,2) as AvgAnswerScore,
    us.RankByQuestions,
    us.FirstQuestionDate,
    us.LastQuestionDate,
    us.AvgDaysBetweenQuestions,
    string_agg(distinct lt.Tag, ', ') as DistinctLatestTags,
    count(distinct dq.PostId) as DuplicateQuestionsCount,
    json_agg(json_build_object(
        'PostId', qcr.PostId, 
        'CloseReason', qcr.CloseReason,
        'CloseDate', qcr.CloseDate
    )) filter (where qcr.PostId is not null) as CloseReasons,
    min(ta.CreationDate) as EarliestTopAnswerDate,
    max(ta.CreationDate) as LatestTopAnswerDate,
    sum(ta.CommentCount) as TotalCommentsOnTopAnswers,
    sum(ta.CommentsByOwner) as OwnerCommentsOnTopAnswers
from UserScoreAgg us
left join LatestTagPerPost lt on lt.PostId in (
    select p.Id from Posts p where p.OwnerUserId = us.UserId and p.PostTypeId = 1
)
left join DuplicateQuestions dq on dq.PostId in (
    select p.Id from Posts p where p.OwnerUserId = us.UserId and p.PostTypeId = 1
)
left join QuestionCloseReasons qcr on qcr.PostId in (
    select p.Id from Posts p where p.OwnerUserId = us.UserId and p.PostTypeId = 1
)
left join TopUsersAnswers tua on tua.UserId = us.UserId
left join Posts ta on ta.OwnerUserId = us.UserId and ta.PostTypeId = 2 and ta.Id in (
    select ta2.Id from TopAnswersWithComments ta2
)
group by us.UserId, us.DisplayName, us.TotalQuestions, us.SumScore, us.GoldBadges, us.SilverBadges, us.BronzeBadges, tua.AnswerCount, tua.AvgAnswerScore, us.RankByQuestions, us.FirstQuestionDate, us.LastQuestionDate, us.AvgDaysBetweenQuestions
order by us.RankByQuestions asc, us.UserId
limit 100;