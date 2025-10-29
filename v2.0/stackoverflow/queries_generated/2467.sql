-- {"query": "2467.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1815} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vt_upvotes.Cnt),0) as TotalUpVotes,
        coalesce(sum(vt_downvotes.Cnt),0) as TotalDownVotes,
        coalesce(max(badges_count.BadgeCount),0) as BadgeCount,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as ActivityRank
    from 
        Users u
        left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
        left join Posts p2 on p2.OwnerUserId = u.Id and p2.PostTypeId = 2
        left join (
            select 
                v.PostId, v.UserId, count(*) as Cnt
            from Votes v
            join VoteTypes vt on vt.Id = v.VoteTypeId and vt.Name = 'UpMod'
            group by v.PostId, v.UserId
        ) vt_upvotes on vt_upvotes.UserId = u.Id
        left join (
            select 
                v.PostId, v.UserId, count(*) as Cnt
            from Votes v
            join VoteTypes vt on vt.Id = v.VoteTypeId and vt.Name = 'DownMod'
            group by v.PostId, v.UserId
        ) vt_downvotes on vt_downvotes.UserId = u.Id
        left join (
            select UserId, count(*) as BadgeCount
            from Badges 
            group by UserId
        ) badges_count on badges_count.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
BadgeDetails as (
    select 
        b.UserId,
        b.Class,
        b.Name,
        count(*) over (partition by b.UserId, b.Class) as ClassBadgeCount
    from Badges b
),
TopQuestions as (
    select 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        array_to_string(
            array (
                select trim(both '<>' from unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')))
            ), ', '
        ) as TagList,
        Rank() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as QuestionRank
    from Posts p
    where p.PostTypeId = 1
      and p.Score is not null
),
QuestionWithAcceptedAnswer as (
    select 
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.TagList,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswererUserId,
        a.CreationDate as AnswerCreationDate
    from TopQuestions q
    left join Posts a on a.Id = q.QuestionId and a.Id = q.QuestionRank
    left join Posts aa on aa.Id = q.QuestionRank
    left join Posts ac on ac.Id = q.AcceptedAnswerId
    left join Posts a on a.Id = q.AcceptedAnswerId
),
PostLinkAnalysis as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        count(*) over (partition by pl.PostId) as TotalLinksPerPost,
        count(*) filter (where lt.Name = 'Duplicate') over (partition by pl.PostId) as DuplicateLinks,
        count(*) filter (where lt.Name = 'Linked') over (partition by pl.PostId) as LinkedLinks
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
UserCommentStats as (
    select 
        c.UserId,
        count(*) as TotalComments,
        avg(length(c.Text)) as AvgCommentLength,
        count(distinct c.PostId) as DistinctCommentedPosts,
        sum(case when c.CreationDate > (current_date - interval '1 year') then 1 else 0 end) as CommentsLastYear
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
ComplexUserMetrics as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionCount,
        u.AnswerCount,
        u.TotalUpVotes,
        u.TotalDownVotes,
        u.BadgeCount,
        coalesce(ucs.TotalComments,0) as TotalComments,
        coalesce(ucs.AvgCommentLength,0) as AvgCommentLength,
        coalesce(ucs.CommentsLastYear,0) as CommentsLastYear,
        case 
            when u.TotalUpVotes + u.TotalDownVotes = 0 then null 
            else round(cast(u.TotalUpVotes as numeric) / nullif((u.TotalUpVotes + u.TotalDownVotes),0), 3) 
        end as UpvoteRatio,
        case
            when u.QuestionCount = 0 then null
            else round(cast(u.AnswerCount as numeric)/nullif(u.QuestionCount,0),3)
        end as AnswerToQuestionRatio
    from RecursiveUserActivity u
    left join UserCommentStats ucs on ucs.UserId = u.UserId
),
FinalSelection as (
    select
        cum.UserId,
        cum.DisplayName,
        cum.Reputation,
        cum.QuestionCount,
        cum.AnswerCount,
        cum.TotalUpVotes,
        cum.TotalDownVotes,
        cum.BadgeCount,
        cum.TotalComments,
        cum.AvgCommentLength,
        cum.CommentsLastYear,
        cum.UpvoteRatio,
        cum.AnswerToQuestionRatio,
        case 
            when cum.AnswerToQuestionRatio is not null and cum.AnswerToQuestionRatio > 1 then 'Prolific Answerer'
            when cum.AnswerToQuestionRatio is not null and cum.AnswerToQuestionRatio between 0.5 and 1 then 'Balanced User'
            else 'Mostly Questioner'
        end as UserType,
        rank() over (order by cum.Reputation desc) as ReputationRank
    from ComplexUserMetrics cum
    where cum.Reputation > 5000 and cum.BadgeCount > 10
)
select 
    fs.UserId,
    fs.DisplayName,
    fs.Reputation,
    fs.QuestionCount,
    fs.AnswerCount,
    fs.TotalUpVotes,
    fs.TotalDownVotes,
    fs.BadgeCount,
    fs.TotalComments,
    fs.AvgCommentLength,
    fs.CommentsLastYear,
    fs.UpvoteRatio,
    fs.AnswerToQuestionRatio,
    fs.UserType,
    fs.ReputationRank,
    pq.QuestionId,
    pq.Title,
    pq.CreationDate as QuestionCreated,
    pq.Score as QuestionScore,
    pq.ViewCount as QuestionViews,
    pq.FavoriteCount as QuestionFavorites,
    pq.TagList,
    pl.AnalysisJson
from FinalSelection fs
left join lateral (
    select json_agg(json_build_object(
        'QuestionId', tq.QuestionId,
        'Title', tq.Title,
        'Score', tq.Score,
        'ViewCount', tq.ViewCount,
        'FavoriteCount', tq.FavoriteCount,
        'TagList', tq.TagList
    ) order by tq.Score desc) as Questions
    from TopQuestions tq 
    where tq.OwnerUserId = fs.UserId and tq.QuestionRank <= 3
) pq(data) on true
left join lateral (
    select json_agg(json_build_object(
        'LinkType', plink.LinkTypeName,
        'TotalLinks', plink.TotalLinksPerPost,
        'Duplicates', plink.DuplicateLinks,
        'Linked', plink.LinkedLinks
    ) order by plink.TotalLinksPerPost desc) as AnalysisJson
    from PostLinkAnalysis plink
    join Posts p on p.Id = plink.PostId
    where p.OwnerUserId = fs.UserId
    limit 5
) pl(data) on true
order by fs.ReputationRank
limit 50;