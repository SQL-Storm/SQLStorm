-- {"query": "2522.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1618} 
with RecursiveUserScores as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        row_number() over (order by u.Reputation desc nulls last, u.Id) as UserRank,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(array_agg(distinct t.TagName) filter (where t.Id is not null), array[]::varchar[]) as TagsWithBadges
    from 
        Users u
        left join Badges b on b.UserId = u.Id
        left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 -- Questions
        left join LATERAL (
            select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
        ) t on true
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopUsersWithAnswers as (
    select 
        rus.UserId,
        rus.DisplayName,
        rus.Reputation,
        rus.UserRank,
        rus.GoldBadges,
        rus.SilverBadges,
        rus.BronzeBadges,
        rus.TagsWithBadges,
        (select count(*) from Posts ans where ans.OwnerUserId = rus.UserId and ans.PostTypeId = 2) as AnswerCount,
        (select count(*) from Votes v where v.UserId = rus.UserId and v.VoteTypeId = 2) as UpVotesGiven,
        (select count(*) from Votes v where v.UserId = rus.UserId and v.VoteTypeId = 3) as DownVotesGiven
    from RecursiveUserScores rus
    where rus.UserRank <= 100
),
PostsWithLinkInfo as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        coalesce(pl.LinkCount,0) as LinkCount,
        coalesce(pl.DuplicateOfCount,0) as DuplicateOfCount
    from 
        Posts p
        left join (
            select 
                pl.PostId,
                count(*) as LinkCount,
                count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateOfCount
            from PostLinks pl
            group by pl.PostId
        ) pl on pl.PostId = p.Id
),
UserPostActivity as (
    select 
        u.Id as UserId,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        max(p.CreationDate) filter (where p.PostTypeId = 1) as LastQuestionDate,
        max(p.CreationDate) filter (where p.PostTypeId = 2) as LastAnswerDate,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalViewsOnQuestions,
        sum(p.FavoriteCount) filter (where p.PostTypeId = 1) as TotalQuestionFavorites
    from 
        Users u
        left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
CloseReasonSummary as (
    select 
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(ph.Id) as CloseCount
    from 
        PostHistory ph
        join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
WindowedPostStats as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        ROW_NUMBER() over (partition by p.OwnerUserId order by p.Score desc nulls last) as rnHighestScorePost,
        RANK() over (order by p.ViewCount desc nulls last) as ViewRank,
        LEAD(p.Score) over (order by p.Score desc nulls last) as NextHighestScore,
        LAG(p.Score) over (order by p.Score desc nulls last) as PrevScore,
        CASE 
            WHEN p.Score >= 100 THEN 'High Score'
            WHEN p.Score >= 10 THEN 'Medium Score'
            ELSE 'Low Score'
        END as ScoreCategory
    from Posts p
    where p.PostTypeId = 1 and p.Score is not null
)
select 
    tu.DisplayName,
    tuple.QuestionCount,
    tuple.AnswerCount,
    tuple.TotalScore,
    tuple.TotalViewsOnQuestions,
    tuple.TotalQuestionFavorites,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.TagsWithBadges,
    ps.Id as TopQuestionId,
    ps.Title as TopQuestionTitle,
    ps.Score as TopQuestionScore,
    ps.ViewCount as TopQuestionViews,
    ps.ScoreCategory,
    coalesce(crs.CloseCount, 0) as CloseVotes,
    coalesce(crs.CloseReasonName, 'No Close Reason') as CommonCloseReason,
    ps.ViewRank,
    latestComment.UserDisplayName as LatestCommenter,
    latestComment.Text as LatestCommentText,
    case when latestComment.UserId = tu.UserId then 'Self-Comment' else 'Other User Comment' end as CommentType
from 
    TopUsersWithAnswers tu
    join UserPostActivity tuple on tuple.UserId = tu.UserId
    left join LATERAL (
        select p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, 
            case 
                when p.Score >= 100 then 'High Score' 
                when p.Score >= 10 then 'Medium Score'
                else 'Low Score'
            end as ScoreCategory
        from Posts p 
        where p.OwnerUserId = tu.UserId and p.PostTypeId = 1
        order by p.Score desc nulls last 
        limit 1
    ) ps on true
    left join CloseReasonSummary crs on crs.CloseReasonId = (
        select ph.Comment from PostHistory ph 
        where ph.PostId = ps.Id and ph.PostHistoryTypeId = 10 
        order by ph.CreationDate desc limit 1
    )
    left join LATERAL (
        select c.UserDisplayName, c.Text, c.UserId from Comments c
        where c.PostId = ps.Id 
        order by c.CreationDate desc limit 1
    ) latestComment on true
where tuple.QuestionCount > 5
order by tu.Reputation desc
limit 50
union all
select 
    concat('Anonymous', u.Id),
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    array[]::varchar[],
    null,
    null,
    null,
    null,
    0,
    'No Close Reason',
    null,
    null,
    'No Comment'
from Users u
where u.Id not in (select UserId from TopUsersWithAnswers)
order by 1;