-- {"query": "537.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1677} 
with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, b.Class
),
UserBadgeRanks as (
    select
        UserId,
        DisplayName,
        coalesce(Class, 4) as BadgeClass,
        BadgeCount,
        row_number() over (partition by UserId order by coalesce(Class, 4)) as rn
    from UserBadgeCounts
),
TopUserBadges as (
    select UserId, DisplayName, BadgeClass, BadgeCount
    from UserBadgeRanks
    where rn = 1
),
PostStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.CommentCount, 0) as CommentCount,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserPostRank
    from Posts p
    join PostTypes pt on p.PostTypeId = pt.Id
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2) -- questions and answers
),
PostLinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        count(*) over (partition by pl.PostId) as LinkCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
AnswerDetails as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.CreationDate,
        u.DisplayName as AnswerOwner,
        vUp.VoteCount as UpVotes,
        vDown.VoteCount as DownVotes,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 2
        group by PostId
    ) vUp on p.Id = vUp.PostId
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) vDown on p.Id = vDown.PostId
    where p.PostTypeId = 2
),
QuestionAnswerSummary as (
    select
        q.PostId as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.OwnerName,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount,
        q.FavoriteCount,
        count(ad.AnswerId) as TotalAnswers,
        max(ad.Score) as MaxAnswerScore,
        avg(ad.Score) filter (where ad.Score is not null) as AvgAnswerScore,
        sum(coalesce(ad.UpVotes, 0)) as TotalAnswerUpVotes,
        sum(coalesce(ad.DownVotes, 0)) as TotalAnswerDownVotes,
        max(case when ad.AnswerRank = 1 then ad.AnswerOwner end) as TopAnswerOwner,
        max(case when ad.AnswerRank = 1 then ad.Score end) as TopAnswerScore
    from PostStats q
    left join AnswerDetails ad on q.PostId = ad.QuestionId
    where q.PostTypeId = 1
    group by q.PostId, q.Title, q.OwnerUserId, q.OwnerName, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount
),
RecentPostActivities as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        ph.CreationDate,
        ph.UserId,
        u.DisplayName as EditorName,
        ph.Comment,
        ph.Text,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as RecentEditRank
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join Users u on ph.UserId = u.Id
    where ph.PostId in (select PostId from PostStats where PostTypeId = 1)
),
FilteredRecentEdits as (
    select *
    from RecentPostActivities
    where RecentEditRank <= 3
),
UserReputationWindow as (
    select
        Id as UserId,
        DisplayName,
        Reputation,
        CreationDate,
        LastAccessDate,
        rank() over (order by Reputation desc) as ReputationRank,
        dense_rank() over (partition by date_trunc('year', CreationDate) order by Reputation desc) as YearlyReputationRank
    from Users
),
DuplicateQuestions as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pq.Title as DuplicateTitle,
        po.Title as OriginalTitle
    from PostLinks pl
    join Posts pq on pl.PostId = pq.Id and pq.PostTypeId = 1
    join Posts po on pl.RelatedPostId = po.Id and po.PostTypeId = 1
    where pl.LinkTypeId = 3 -- Duplicate link type
)
select
    qas.QuestionId,
    qas.Title,
    qas.OwnerName,
    qas.QuestionScore,
    qas.QuestionViews,
    qas.AnswerCount,
    qas.FavoriteCount,
    qas.TotalAnswers,
    qas.MaxAnswerScore,
    qas.AvgAnswerScore,
    qas.TotalAnswerUpVotes,
    qas.TotalAnswerDownVotes,
    qas.TopAnswerOwner,
    qas.TopAnswerScore,
    tnb.BadgeClass,
    tnb.BadgeCount,
    urw.Reputation,
    urw.ReputationRank,
    urw.YearlyReputationRank,
    array_agg(distinct dt.DuplicateTitle) filter (where dt.DuplicateQuestionId = qas.QuestionId) as DuplicateTitles,
    string_agg(distinct fr.Comment || ' by ' || coalesce(fr.EditorName, 'unknown'), ' | ') as RecentEditComments
from QuestionAnswerSummary qas
left join TopUserBadges tnb on qas.OwnerUserId = tnb.UserId
left join UserReputationWindow urw on qas.OwnerUserId = urw.UserId
left join DuplicateQuestions dt on qas.QuestionId = dt.OriginalQuestionId
left join FilteredRecentEdits fr on qas.QuestionId = fr.PostId
group by
    qas.QuestionId, qas.Title, qas.OwnerName, qas.QuestionScore, qas.QuestionViews, qas.AnswerCount, qas.FavoriteCount,
    qas.TotalAnswers, qas.MaxAnswerScore, qas.AvgAnswerScore, qas.TotalAnswerUpVotes, qas.TotalAnswerDownVotes,
    qas.TopAnswerOwner, qas.TopAnswerScore,
    tnb.BadgeClass, tnb.BadgeCount,
    urw.Reputation, urw.ReputationRank, urw.YearlyReputationRank
having qas.TotalAnswers > 5 and qas.QuestionScore > 10
order by qas.QuestionScore desc, qas.TotalAnswers desc
limit 50;