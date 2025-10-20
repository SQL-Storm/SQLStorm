with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        u.Reputation,
        coalesce(badge_stats.GoldCount, 0) as GoldBadges,
        coalesce(badge_stats.SilverCount, 0) as SilverBadges,
        coalesce(badge_stats.BronzeCount, 0) as BronzeBadges,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as PostRankByOwner,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as GlobalRank
    from
        Posts p
        left join Users u on p.OwnerUserId = u.Id
        left join (
            select
                UserId,
                sum(case when Class = 1 then 1 else 0 end) as GoldCount,
                sum(case when Class = 2 then 1 else 0 end) as SilverCount,
                sum(case when Class = 3 then 1 else 0 end) as BronzeCount
            from Badges
            group by UserId
        ) badge_stats on badge_stats.UserId = p.OwnerUserId
    where
        p.PostTypeId in (1, 2)
),
TaggedQuestions as (
    select
        Id,
        unnest(string_to_array(substring(Tags from 2 for char_length(Tags) - 2), '><')) as TagName
    from Posts
    where PostTypeId = 1 and Tags is not null
),
FilteredTaggedUsers as (
    select
        rp.OwnerUserId,
        rp.Id as PostId,
        rp.Title,
        rp.Score,
        tt.TagName,
        count(distinct replies.Id) as AnswersCount
    from
        RankedPosts rp
        inner join TaggedQuestions tt on rp.Id = tt.Id
        left join Posts replies on replies.ParentId = rp.Id and replies.PostTypeId = 2
    where
        rp.PostRankByOwner <= 3
    group by rp.OwnerUserId, rp.Id, rp.Title, rp.Score, tt.TagName
),
AnswerImpact as (
    select
        p.Id as AnswerId,
        p.OwnerUserId,
        p.ParentId as QuestionId,
        coalesce(vt.UpVotes, 0) - coalesce(vt.DownVotes, 0) as NetVotes,
        p.CommentCount,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate) as AnswerRank
    from
        Posts p
        left join (
            select
                PostId,
                sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
                sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
            from Votes
            group by PostId
        ) vt on p.Id = vt.PostId
    where p.PostTypeId = 2
),
AuteurFilters as (
    select distinct u.Id, u.DisplayName, u.Reputation,
    case
        when u.Reputation > 5000 then 'Expert'
        when u.Reputation > 1000 then 'Intermediate'
        else 'Novice'
    end as UserRank
    from Users u
    where u.Id is not null
),
QuestionsWithStatus as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        case when qc.FirstCloseReasonId is not null then 'Closed' else 'Open' end as Status,
        qc.FirstCloseReasonId,
        art.RankByVotes
    from Posts q
    left join (
        select
            ph.PostId,
            min(cast(ph.Comment as integer)) over (partition by ph.PostId) as FirstCloseReasonId
        from PostHistory ph
        where ph.PostHistoryTypeId = 10
    ) qc on q.Id = qc.PostId
    left join (
        select
            a.ParentId as PostId,
            dense_rank() over (partition by a.ParentId order by count(v.Id) desc) as RankByVotes
        from
            Posts a
            join Votes v on v.PostId = a.Id
        group by a.ParentId
    ) art on q.Id = art.PostId
    where q.PostTypeId = 1
),
DupeLinkedPosts as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name in ('Duplicate','Linked')
),
LastBadges as (
    select b1.UserId, b1.Date
    from Badges b1
    inner join (
        select UserId, max(Date) as Date
        from Badges
        where Class = 1
        group by UserId
    ) b2 on b1.UserId = b2.UserId and b1.Date = b2.Date and b1.Class = 1
)
select
    af.Id as UserId,
    af.DisplayName,
    af.Reputation,
    af.UserRank
from AuteurFilters af
limit 100;