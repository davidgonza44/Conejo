"""Lógica de negocio de categorías."""
from app.extensions import db
from app.models import Category, Product
from app.services.exceptions import ConflictError, NotFoundError, ValidationError


def _validate_name(data: dict, exclude_id: int | None = None) -> str:
    name = (data.get("name") or "").strip()
    if not name:
        raise ValidationError("El nombre de la categoría es obligatorio.")

    query = Category.query.filter(Category.name == name)
    if exclude_id is not None:
        query = query.filter(Category.id != exclude_id)
    if query.first() is not None:
        raise ConflictError(f"Ya existe una categoría con el nombre '{name}'.")
    return name


def get_category_or_404(category_id: int) -> Category:
    category = db.session.get(Category, category_id)
    if category is None:
        raise NotFoundError(f"La categoría con id {category_id} no existe.")
    return category


def list_categories() -> list[Category]:
    return Category.query.order_by(Category.name).all()


def create_category(data: dict) -> Category:
    name = _validate_name(data)
    category = Category(
        name=name,
        description=(data.get("description") or "").strip() or None,
    )
    db.session.add(category)
    db.session.commit()
    return category


def update_category(category_id: int, data: dict) -> Category:
    category = get_category_or_404(category_id)

    if "name" in data:
        category.name = _validate_name(data, exclude_id=category.id)
    if "description" in data:
        category.description = (data.get("description") or "").strip() or None

    db.session.commit()
    return category


def delete_category(category_id: int) -> None:
    category = get_category_or_404(category_id)

    products_count = Product.query.filter_by(category_id=category.id).count()
    if products_count > 0:
        raise ConflictError(
            f"No se puede eliminar la categoría '{category.name}' porque tiene "
            f"{products_count} producto(s) asociado(s). Reasigne los productos primero."
        )

    db.session.delete(category)
    db.session.commit()
