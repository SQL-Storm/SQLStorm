with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Name is not null
),
TopUserBadges as (
    select distinct UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostScoresRanked as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as UserPostRank,
        dense_rank() over (order by p.Score desc) as GlobalScoreRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
AcceptedAnswersWithAuthors as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        coalesce(u.DisplayName, 'Community') as AnswerAuthorName
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        p1.OwnerUserId as PostOwner,
        p2.OwnerUserId as RelatedPostOwner
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    where lt.Name = 'Duplicate'
),
QuestionsWithCloseReasons as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes cr on cast(ph.Comment as integer) = cr.Id
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct case when v.VoteTypeId = 2 then v.Id end) as UpVotesReceived,
        count(distinct case when v.VoteTypeId = 3 then v.Id end) as DownVotesReceived,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
RankedQuestionsCTE as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerDisplayName,
        row_number() over (partition by p.Tags order by p.Score desc) as RankByTags
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Tags is not null
),
FilteredQuestions as (
    select *
    from RankedQuestionsCTE
    where RankByTags <= 5
),
ComplexStringAggregates as (
    select
        q.OwnerUserId,
        string_agg(distinct q.tag, ', ') as DistinctTags,
        count(distinct q.Id) as QuestionsCount
    from (
        select
            p.Id,
            p.OwnerUserId,
            unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tag
        from Posts p
        where p.PostTypeId = 1 and p.Tags is not null
    ) q
    group by q.OwnerUserId
)
select
    u.Id as UserId,
    u.DisplayName,
    us.QuestionCount,
    us.AnswerCount,
    us.CommentCount,
    us.UpVotesReceived,
    us.DownVotesReceived,
    coalesce(csa.DistinctTags, '') as UserTagList,
    coalesce(csa.QuestionsCount, 0) as UserTaggedQuestionCount,
    tab.BadgeName as TopBadge,
    tab.Class as BadgeClass,
    par.GlobalScoreRank as PostGlobalRank,
    par.UserPostRank,
    parr.Title as PostTitle,
    aa.Title as AcceptedQuestionTitle,
    coalesce(dpl.PostTitle, '') as DuplicatePostTitle,
    coalesce(dpl.RelatedPostTitle, '') as DuplicateRelatedTitle,
    qcr.CloseReason,
    qcr.CloseDate
from Users u
left join UserActivitySummary us on us.UserId = u.Id
left join ComplexStringAggregates csa on csa.OwnerUserId = u.Id
left join TopUserBadges tab on tab.UserId = u.Id and tab.Class = (
    select min(t2.Class)
    from TopUserBadges t2
    where t2.UserId = u.Id
)
left join PostScoresRanked par on par.OwnerUserId = u.Id and par.UserPostRank = 1
left join Posts parr on parr.Id = par.PostId
left join AcceptedAnswersWithAuthors aa on aa.QuestionOwner = u.Id
left join DuplicateLinks dpl on dpl.PostOwner = u.Id or dpl.RelatedPostOwner = u.Id
left join QuestionsWithCloseReasons qcr on qcr.PostId = par.PostId
where u.Reputation > 1000
and (
    (par.Score > 10 and par.PostTypeId = 1)
    or (us.AnswerCount > 5 and us.UpVotesReceived > 50)
)
order by us.UpVotesReceived desc, par.GlobalScoreRank
limit 100;