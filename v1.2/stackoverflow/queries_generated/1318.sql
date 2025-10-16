-- {"query": "1318.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1946} 
with RecentUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id and b.Date > current_date - interval '180 day'
    group by u.Id, u.DisplayName
),
PostScoresAndVotes as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(vote_data.UpVotes,0) as UpVotes,
        coalesce(vote_data.DownVotes,0) as DownVotes,
        coalesce(vote_data.Favorites,0) as Favorites,
        coalesce(comment_counts.CommentCount, 0) as CommentCount,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as IsAcceptedQuestion
    from Posts p
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes,
            sum(case when VoteTypeId = 5 then 1 else 0 end) as Favorites
        from Votes
        group by PostId
    ) vote_data on vote_data.PostId = p.Id
    left join (
        select PostId, count(*) as CommentCount from Comments group by PostId
    ) comment_counts on comment_counts.PostId = p.Id
),
AnswerRanking as (
    select
        p.ParentId as QuestionId,
        p.Id as AnswerId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
QuestionDuplicates as (
    select
        pl.PostId as DuplicateId,
        pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
QuestionsWithDuplicates as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        count(distinctqd.DuplicateId) as DupCount
    from Posts q
    left join (
        select OriginalQuestionId, DuplicateId from QuestionDuplicates
    ) distinctqd on distinctqd.OriginalQuestionId = q.Id
    where q.PostTypeId=1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
TopUsersQuestionsAndBadges as (
    select
        u.Id,
        u.DisplayName,
        count(distinct q.QuestionId) as TotalQuestions,
        sum(case when q.DupCount > 0 then 1 else 0 end) as QuestionsWithDuplicates,
        rb.GoldBadges,
        rb.SilverBadges,
        rb.BronzeBadges,
        rb.LastBadgeDate,
        u.Reputation
    from Users u
    left join QuestionsWithDuplicates q on q.OwnerUserId = u.Id
    left join RecentUserBadges rb on rb.UserId = u.Id
    group by u.Id, u.DisplayName, rb.GoldBadges, rb.SilverBadges, rb.BronzeBadges, rb.LastBadgeDate, u.Reputation
    having count(distinct q.QuestionId) > 20  -- keep only active askers
),
FinalAnswerStats as (
    select
        au.Id as UserId,
        au.DisplayName,
        count(a.AnswerId) as TotalAnswers,
        sum(case when a.AnswerRank = 1 then 1 else 0 end) as TopRankAnswers,
        avg(case when a.Score >=0 then a.Score else null end) as AvgAnswerScore,
        max(a.CreationDate) as LastAnswerDate
    from Users au
    left join AnswerRanking a on a.OwnerUserId = au.Id
    group by au.Id, au.DisplayName
),
CTE_UserEngagement as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        totalq.TotalQuestions,
        coalesce(totalq.QuestionsWithDuplicates,0) as QuestionsWithDuplicates,
        coalesce(totalb.GoldBadges,0) as GoldBadges,
        coalesce(totalb.SilverBadges,0) as SilverBadges,
        coalesce(totalb.BronzeBadges,0) as BronzeBadges,
        finala.TotalAnswers,
        finala.TopRankAnswers,
        coalesce(finala.AvgAnswerScore,0) as AvgAnswerAnswerScore,
        u.LastAccessDate,
        greatest(
            coalesce(u.CreationDate,'1900-01-01'),
            coalesce(finala.LastAnswerDate,'1900-01-01'),
            coalesce(totalb.LastBadgeDate,'1900-01-01')
        ) as MostRecentActivity
    from Users u
    left join TopUsersQuestionsAndBadges totalq on totalq.Id = u.Id
    left join RecentUserBadges totalb on totalb.UserId = u.Id
    left join FinalAnswerStats finala on finala.UserId = u.Id
    where u.Reputation > 1000
),
QuestionsWithWindowedScores as (
    select  
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        row_number() over (partition by p.Tags order by p.Score desc nulls last) as RankPerTag,
        count(*) over (partition by p.Tags) as TotalPostsInTag,
        substring(p.Body from '<p>(.*?)</p>') as FirstParagraph, -- extract first <p> block as basic string extraction
        case when p.ClosedDate is null then 'Open' else 'Closed' end as Status
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
HighEngagementOpenTopQuestionAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.Status,
        a.Id as AnswerId,
        a.OwnerUserId as AnswererId,
        au.DisplayName as AnswererName,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        case when a.Score >= 10 then 'High score' else 'Normal' end as AnswerQuality
    from QuestionsWithWindowedScores q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    join Users au on au.Id = a.OwnerUserId
    where q.Status = 'Open' and q.RankPerTag = 1 and q.TotalPostsInTag > 15
),
XmlAggDups as (
    select q.OriginalQuestionId, 
           string_agg(dup.Title, ' ||| ') as DuplicateTitles
    from QuestionDuplicates qd
    join Posts dup on dup.Id = qd.DuplicateId
    join QuestionsDuplicates q on qm.postid=os.questionid
    group by q.OriginalQuestionId
),
Bedroom1 as (
    select
        u.Id as UserId,
        u.DisplayName,
        r.ReputationRank
    from (
        select Id, DENSE_RANK() over (order by Reputation desc) as ReputationRank from Users
    ) as r
    join Users u on u.Id = r.Id
    where r.ReputationRank <= 50
)
select
    eu.Id as UserId,
    eu.DisplayName,
    eu.Reputation,
    eu.TotalQuestions,
    eu.QuestionsWithDuplicates,
    eu.GoldBadges,
    eu.SilverBadges,
    eu.BronzeBadges,
    eu.TotalAnswers,
    eu.TopRankAnswers,
    round(eu.AvgAnswerAnswerScore::numeric,2) as AvgAnswerScore,
    eu.LastAccessDate,
    eu.MostRecentActivity,
    hlta.QuestionId,
    hlta.Title as TopQuestionTitle,
    hlta.Tags,
    hlta.QuestionScore,
    hlta.Status as QuestionStatus,
    hlta.AnswerId,
    hlta.AnswererId,
    hlta.AnswererName,
    hlta.AnswerScore,
    hlta.AnswerQuality
from CTE_UserEngagement eu
left join HighEngagementOpenTopQuestionAnswers hlta on hlta.AnswererId = eu.Id
where eu.MostRecentActivity > current_date - interval '1 year'
order by eu.Reputation desc, hlta.QuestionScore desc nulls last, hlta.AnswerScore desc nulls last
limit 100;