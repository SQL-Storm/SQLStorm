with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        p.Tags,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserPostRank,
        count(*) over (partition by p.OwnerUserId) as UserPostCount
    from
        Posts p
        left join Users u on p.OwnerUserId = u.Id
    where
        p.PostTypeId in (1, 2) -- Questions or Answers
        and p.Score is not null
),
AcceptedAnswersWithVotes as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score as AnswerScore,
        p.CreationDate as AnswerCreationDate,
        (
            select count(*)
            from Votes v
            where v.PostId = p.Id and v.VoteTypeId = 2 -- UpMod
        ) as UpVotesCount,
        (
            select count(*)
            from Votes v
            where v.PostId = p.Id and v.VoteTypeId = 3 -- DownMod
        ) as DownVotesCount
    from Posts p
    where p.PostTypeId = 2
),
QuestionsWithAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        aa.AnswerId,
        aa.AnswerScore,
        aa.UpVotesCount,
        aa.DownVotesCount,
        u.DisplayName as QuestionOwner,
        u.Reputation as QuestionOwnerReputation,
        u.Location as QuestionOwnerLocation,
        q.OwnerUserId
    from Posts q
    left join AcceptedAnswersWithVotes aa on q.AcceptedAnswerId = aa.AnswerId
    left join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
UserBadgeStats as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        count(*) over (partition by b.UserId) as TotalBadges,
        rank() over (partition by b.UserId order by b.Class asc, b.Date asc) as BadgeRankPerUser
    from Badges b
),
CommentsWithUser as (
    select
        c.Id as CommentId,
        c.PostId,
        c.Score,
        c.Text,
        c.CreationDate,
        coalesce(u.DisplayName, c.UserDisplayName, 'Anonymous') as CommentUserName,
        u.Reputation as CommentUserReputation
    from Comments c
    left join Users u on c.UserId = u.Id
),
PostLinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkType,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        count(distinct p.Id) as TotalPosts,
        count(distinct b.Id) as TotalBadges,
        count(distinct c.Id) as TotalComments,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(coalesce(p.CreationDate, c.CreationDate)) as LastActivityDate,
        row_number() over (order by u.Reputation desc) as RankByReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.Location
),
FilteredPosts as (
    select *
    from Posts
    where
        PostTypeId = 1
        and CreationDate > '2010-01-01'
        and (Tags like '%<sql>%' or Tags like '%<database>%')
),
QuestionsWithDuplicates as (
    select
        q.Id as QuestionId,
        q.Title,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id and pl.LinkTypeId = 3 -- Duplicate
    left join Posts pl2 on pl.RelatedPostId = pl2.Id and pl2.PostTypeId = 1
    where q.PostTypeId = 1
    group by q.Id, q.Title
),
FinalResult as (
    select
        qp.QuestionId,
        qp.Title,
        qp.QuestionCreationDate,
        qp.QuestionScore,
        qp.ViewCount,
        qp.Tags,
        qp.AnswerId,
        qp.AnswerScore,
        qp.UpVotesCount,
        qp.DownVotesCount,
        qp.QuestionOwner,
        qp.QuestionOwnerReputation,
        qp.QuestionOwnerLocation,
        us.TotalBadges,
        us.BadgeName,
        us.Class as BadgeClass,
        coalesce(cd.DuplicateCount, 0) as DuplicateCount,
        ca.CommentCount,
        cs.TotalComments as OwnerCommentCount,
        ua.RankByReputation,
        qp.OwnerUserId
    from QuestionsWithAcceptedAnswers qp
    left join (
        select
            b.UserId,
            max(b.TotalBadges) as TotalBadges,
            max(b.BadgeName) as BadgeName,
            max(b.Class) as Class
        from UserBadgeStats b
        group by b.UserId
    ) us on qp.OwnerUserId = us.UserId
    left join (
        select
            p.Id as PostId,
            count(c.Id) as CommentCount
        from Posts p
        left join Comments c on c.PostId = p.Id
        group by p.Id
    ) ca on qp.QuestionId = ca.PostId
    left join (
        select
            u.Id as UserId,
            count(c.Id) as TotalComments
        from Users u
        left join Comments c on c.UserId = u.Id
        group by u.Id
    ) cs on cs.UserId = qp.OwnerUserId
    left join QuestionsWithDuplicates cd on qp.QuestionId = cd.QuestionId
    left join UserActivityWindow ua on ua.UserId = qp.OwnerUserId
    where
        qp.QuestionScore >= all (
            select max(p2.Score)
            from Posts p2
            where p2.AcceptedAnswerId = qp.AnswerId and p2.PostTypeId = 2
        )
)
select
    fr.QuestionId,
    fr.Title,
    fr.QuestionCreationDate,
    fr.QuestionScore,
    fr.ViewCount,
    fr.Tags,
    fr.AnswerId,
    fr.AnswerScore,
    fr.UpVotesCount,
    fr.DownVotesCount,
    coalesce(fr.QuestionOwner, 'Unknown User') as QuestionOwner,
    fr.QuestionOwnerReputation,
    coalesce(fr.QuestionOwnerLocation, 'Unknown') as QuestionOwnerLocation,
    fr.TotalBadges,
    fr.BadgeName,
    case
        when fr.BadgeClass = 1 then 'Gold'
        when fr.BadgeClass = 2 then 'Silver'
        when fr.BadgeClass = 3 then 'Bronze'
        else 'None'
    end as BadgeClass,
    fr.DuplicateCount,
    fr.CommentCount,
    fr.OwnerCommentCount,
    fr.RankByReputation,
    -- Complex calculated fields:
    (cast(fr.QuestionScore as float) / nullif(fr.ViewCount,0)) as ScoreViewRatio,
    (length(coalesce(fr.Tags, '')) - length(replace(coalesce(fr.Tags, ''), '><', '')) + 1) as TagCount,
    -- Concatenate Title and Tags with NULL safe logic and trimming
    trim(coalesce(fr.Title, '') || ' || ' || coalesce(fr.Tags, '')) as TitleTagsConcat
from FinalResult fr
where fr.RankByReputation <= 100
order by fr.QuestionScore desc, fr.ViewCount desc
limit 50;