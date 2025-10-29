-- {"query": "2308.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1388} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as Rnk
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
TopUserBadges as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where Rnk <= 3
),
QuestionStats as (
    select 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        /* Calculate ratio with NULL logic to avoid division by zero */
        case 
            when (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) = 0 then null
            else cast(
                (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as float) / 
                (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3)
        end as UpDownRatio
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate >= current_date - interval '180 days'
),
AnswerRanks as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
TopAnswers as (
    select AnswerId, QuestionId, OwnerUserId, Score, CreationDate, AnswerRank
    from AnswerRanks
    where AnswerRank <= 2
),
QuestionWithAnswers as (
    select 
        qs.QuestionId,
        qs.Title,
        qs.OwnerUserId,
        qs.CreationDate as QuestionCreation,
        qs.Score as QuestionScore,
        qs.ViewCount,
        qs.Tags,
        qs.AnswerCount,
        qs.FavoriteCount,
        qs.CommentCount,
        qs.UpVotes,
        qs.DownVotes,
        qs.UpDownRatio,
        ta.AnswerId,
        ta.OwnerUserId as AnswerOwner,
        ta.Score as AnswerScore,
        ta.CreationDate as AnswerCreation,
        ta.AnswerRank
    from QuestionStats qs
    left join TopAnswers ta on qs.QuestionId = ta.QuestionId
),
PostLinkSummary as (
    select 
        pl.PostId,
        sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as DuplicateLinks,
        sum(case when lt.Name = 'Linked' then 1 else 0 end) as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
QuestionsEnriched as (
    select 
        qwa.*,
        pls.DuplicateLinks,
        pls.LinkedPosts,
        /* String operation: extract first tag from Tags string, tags are encoded in angle brackets: e.g. <tag1><tag2> */
        substring(qwa.Tags from '<([^>]+)>') as FirstTag,
        /* Null-safe date difference */
        case 
            when qwa.AnswerCreation is not null then 
                extract(epoch from (qwa.AnswerCreation - qwa.QuestionCreation))/3600.0
            else null
        end as HoursToTopAnswer
    from QuestionWithAnswers qwa
    left join PostLinkSummary pls on qwa.QuestionId = pls.PostId
),
FilteredQuestions as (
    select * from QuestionsEnriched
    where (AnswerCount > 0 or FavoriteCount > 5) and 
          (DuplicateLinks is null or DuplicateLinks < 3) and
          (HoursToTopAnswer is null or HoursToTopAnswer < 72)
),
CloseVotesCounts as (
    select 
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotes
    from PostHistory ph
    group by ph.PostId
),
FinalSelection as (
    select 
        fq.QuestionId,
        fq.Title,
        fq.OwnerUserId,
        u.DisplayName as OwnerName,
        fq.QuestionCreation,
        fq.QuestionScore,
        fq.ViewCount,
        fq.FirstTag,
        fq.AnswerCount,
        fq.FavoriteCount,
        fq.CommentCount,
        fq.UpVotes,
        fq.DownVotes,
        fq.UpDownRatio,
        fq.AnswerId,
        fq.AnswerOwner,
        aown.DisplayName as AnswerOwnerName,
        fq.AnswerScore,
        fq.AnswerCreation,
        fq.AnswerRank,
        fq.DuplicateLinks,
        fq.LinkedPosts,
        fq.HoursToTopAnswer,
        coalesce(cv.CloseVotes,0) as CloseVotes,
        coalesce(cv.ReopenVotes,0) as ReopenVotes,
        /* correlated subquery to get count of gold badges for question owner */
        (select count(*) from Badges b where b.UserId = fq.OwnerUserId and b.Class = 1) as OwnerGoldBadges,
        /* string concatenation to create a summary */
        ('Q:'+ coalesce(fq.Title,'') || ' | Tag:' || coalesce(fq.FirstTag,'') || ' | Score:' || fq.QuestionScore::text ) as Summary
    from FilteredQuestions fq
    left join Users u on fq.OwnerUserId = u.Id
    left join Users aown on fq.AnswerOwner = aown.Id
    left join CloseVotesCounts cv on fq.QuestionId = cv.PostId
)
select *
from FinalSelection
order by CloseVotes desc, OwnerGoldBadges desc, QuestionScore desc, AnswerScore desc
limit 50;