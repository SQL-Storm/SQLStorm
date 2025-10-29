-- {"query": "2551.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1600} 
with RecursiveUserPosts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
LatestUserPosts as (
    select 
        UserId,
        DisplayName,
        PostId,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        Tags
    from RecursiveUserPosts
    where rn <= 5
),
PostCommentsSummary as (
    select 
        c.PostId,
        count(*) as TotalComments,
        sum(case when c.Score is not null and c.Score > 0 then 1 else 0 end) as PositiveComments,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Unknown') || ':' || left(c.Text, 20), ' | ') as SampleComments
    from Comments c
    group by c.PostId
),
PostAnswerStats as (
    select 
        q.Id as QuestionId,
        count(a.Id) as AnswerCount,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Score > 10 then 1 else 0 end) as HighScoreAnswers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
UserBadgeRanks as (
    select 
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
UserActivityRank as (
    select 
        u.Id as UserId,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        max(p.CreationDate) as LastPostDate,
        max(coalesce(p.Score,0)) as MaxPostScore,
        count(distinct ph.PostId) as PostsWithHistory,
        count(ph.Id) as TotalPostEdits
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id
    group by u.Id
),
DuplicatedQuestions as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        l.Name as LinkType,
        q1.Title as DuplicateTitle,
        q2.Title as OriginalTitle
    from PostLinks pl
    inner join LinkTypes l on l.Id = pl.LinkTypeId
    inner join Posts q1 on q1.Id = pl.PostId and q1.PostTypeId = 1
    inner join Posts q2 on q2.Id = pl.RelatedPostId and q2.PostTypeId = 1
    where l.Name ilike '%duplicate%'
),
QuestionCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        min(ph.CreationDate) as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) 
    where ph.PostHistoryTypeId = 10 and crt.Id is not null
    group by ph.PostId, crt.Name
),
RankedAnswers as (
    select 
        a.Id,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        u.DisplayName as AnswerOwner,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
TopAnswerDetails as (
    select 
        q.Id as QuestionId,
        q.Title,
        r.AnswerOwner,
        r.Score as TopAnswerScore,
        r.CreationDate as TopAnswerDate,
        case 
          when q.AcceptedAnswerId = r.Id then 'Yes' 
          else 'No' 
        end as IsAccepted,
        q.ViewCount,
        q.Score as QuestionScore,
        coalesce(pc.TotalComments,0) as CommentCount
    from Posts q
    left join RankedAnswers r on r.QuestionId = q.Id and r.AnswerRank = 1
    left join PostCommentsSummary pc on pc.PostId = q.Id
    where q.PostTypeId = 1
),
FinalResult as (
    select 
        u.Id as UserId,
        u.DisplayName as UserName,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.TotalPostEdits,
        las.PostId,
        las.CreationDate as PostCreation,
        case las.PostTypeId 
            when 1 then 'Question'
            when 2 then 'Answer'
            else 'Other'
        end as PostType,
        las.Score,
        las.ViewCount,
        pa.AnswerCount,
        pa.AvgAnswerScore,
        pa.HighScoreAnswers,
        dq.DuplicateQuestionId,
        dq.OriginalQuestionId,
        dq.LinkType as DuplicationType,
        qcr.CloseReason,
        topa.TopAnswerScore,
        topa.IsAccepted as TopAnswerIsAccepted,
        case 
            when ua.LastPostDate > now() - interval '30 days' then 'Active'
            when ua.LastPostDate between now() - interval '90 days' and now() - interval '30 days' then 'Moderately Active'
            else 'Inactive'
        end as ActivityStatus,
        substring(coalesce(las.Tags, '') from '[^<>]+') as FirstTag,
        length(coalesce(las.Body, '')) as BodyLength,
        pc.SampleComments
    from Users u
    left join UserBadgeRanks ur on ur.UserId = u.Id
    left join UserActivityRank ua on ua.UserId = u.Id
    left join LatestUserPosts las on las.UserId = u.Id
    left join PostAnswerStats pa on pa.QuestionId = las.PostId
    left join DuplicatedQuestions dq on dq.DuplicateQuestionId = las.PostId
    left join QuestionCloseReasons qcr on qcr.PostId = las.PostId
    left join TopAnswerDetails topa on topa.QuestionId = las.PostId
    left join PostCommentsSummary pc on pc.PostId = las.PostId
    where u.Reputation > 1000
)
select * from FinalResult
where (GoldBadges + SilverBadges + BronzeBadges) > 10
and (QuestionsCount > 5 or AnswersCount > 10)
order by GoldBadges desc, ActivityStatus, ua.LastPostDate desc NULLS LAST
limit 100;